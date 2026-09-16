import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../app/application_providers.dart';
import '../../../core/config/app_environment.dart';
import '../../../core/realtime/signalr_gateway.dart';
import '../../../core/native/native.dart';
import '../../../core/services/clipboard_service.dart';
import '../../../core/services/file/attachment_cache.dart';
import '../../../core/services/file/attachment_transfer_service.dart';
import '../../../core/services/file/file_picker_service.dart';
import '../../../core/services/media/media_service.dart';
import '../../../core/services/media/audio_playback_service.dart';
import '../../../core/services/media/voice_cache_service.dart';
import 'chat_unread_divider.dart';
import 'ai_stream_change_bus.dart';
import '../data/datasources/message_api.dart';
import '../data/datasources/message_dao.dart';
import '../data/models/chat_message.dart';
import '../data/repositories/message_repository.dart';
import '../../session/data/models/session_summary.dart';
import '../../session/data/models/session_summary_helpers.dart';
import '../../session/data/datasources/session_dao.dart';
import '../../session/data/repositories/session_repository.dart';
import '../../session/data/session_change_bus.dart';
import '../../chat_settings/data/models/chat_member.dart';
import '../../chat_settings/data/repositories/chat_settings_repository.dart';

final messageRepositoryProvider = Provider<MessageRepository>(
  (ref) => MessageRepository(
    api: MessageApi(ref.watch(apiClientProvider)),
    dao: MessageDao(ref.watch(unifiedDatabaseProvider)),
    sessionDao: SessionDao(ref.watch(unifiedDatabaseProvider)),
    sessionChangeBus: ref.watch(sessionChangeBusProvider),
  ),
);

final voiceCacheServiceProvider = Provider<VoiceCacheService>(
  (ref) => createVoiceCacheService(ref.watch(apiClientProvider)),
);

final audioPlaybackServiceProvider =
    ChangeNotifierProvider<AudioPlaybackService>((ref) {
      return AudioPlaybackService(
        environment: ref.watch(appEnvironmentProvider),
        voiceCacheService: ref.watch(voiceCacheServiceProvider),
        nativeSensor: ref.watch(nativeSensorProvider),
      );
    });

final attachmentTransferServiceProvider =
    ChangeNotifierProvider<AttachmentTransferService>((ref) {
      return AttachmentTransferService(
        client: ref.watch(apiClientProvider),
        environment: ref.watch(appEnvironmentProvider),
        filePickerService: ref.watch(filePickerServiceProvider),
      );
    });

class ChatController extends ChangeNotifier {
  ChatController(
    this._repository,
    this._sessionRepository, {
    required FilePickerService filePickerService,
    required AttachmentTransferService attachmentTransferService,
    required MediaService mediaService,
    required AudioPlaybackService audioPlaybackService,
    required SessionChangeBus sessionChangeBus,
    required ClipboardService clipboardService,
    required ChatSettingsRepository chatSettingsRepository,
    required AiStreamChangeBus aiStreamChangeBus,
    required SignalRGateway signalRGateway,
    required this.ownerId,
    required this.sessionUnitId,
    required String initialTitle,
  }) : _filePickerService = filePickerService,
       _attachmentTransferService = attachmentTransferService,
       _mediaService = mediaService,
       _audioPlaybackService = audioPlaybackService,
       _sessionChangeBus = sessionChangeBus,
       _clipboardService = clipboardService,
       _chatSettingsRepository = chatSettingsRepository,
       _aiStreamChangeBus = aiStreamChangeBus,
       _signalRGateway = signalRGateway,
       _title = initialTitle;
  static const pageSize = 30;
  static const initialPageSize = 10;
  final MessageRepository _repository;
  final SessionRepository _sessionRepository;
  final FilePickerService _filePickerService;
  final AttachmentTransferService _attachmentTransferService;
  final MediaService _mediaService;
  final AudioPlaybackService _audioPlaybackService;
  final SessionChangeBus _sessionChangeBus;
  final ClipboardService _clipboardService;
  final ChatSettingsRepository _chatSettingsRepository;
  final AiStreamChangeBus _aiStreamChangeBus;
  final SignalRGateway _signalRGateway;
  final int ownerId;
  final String sessionUnitId;
  final List<ChatMessage> _messages = <ChatMessage>[];
  final Map<String, SelectedFile> _pendingFiles = <String, SelectedFile>{};
  final Map<String, Uint8List> _imagePreviews = <String, Uint8List>{};
  final Map<String, double> uploadProgress = <String, double>{};
  bool isLoading = false;
  bool isSending = false;
  bool isLoadingLatest = false;
  bool hasMore = true;
  Object? error;
  SessionSummary? friend;
  String _title;
  StreamSubscription<SessionChangeEvent>? _sessionChangeSubscription;
  StreamSubscription<AiStreamEvent>? _aiStreamSubscription;
  StreamSubscription<SignalRAppEvent>? _signalRSubscription;
  Timer? _aiStreamElapsedTimer;
  Timer? _aiRunRecoveryTimer;
  bool _isRecoveringAfterRealtimeReconnect = false;
  final Map<int, AiStreamReply> _aiStreamReplies = <int, AiStreamReply>{};
  List<AiRunRecord> _recentAiRuns = const <AiRunRecord>[];
  ChatMessage? quoting;
  bool selectionMode = false;
  int newMessageCount = 0;
  bool _viewingLatest = true;
  int? _lastSubmittedReadMessageId;
  int? _initialUnreadDividerMessageId;
  final Set<String> selectedLocalIds = <String>{};
  final List<ChatMember> mentionMembers = <ChatMember>[];
  final Map<String, String> _mentionedTokens = <String, String>{};
  bool mentionVisible = false;
  bool mentionLoading = false;
  bool mentionHasMore = false;
  String _mentionKeyword = '';
  int _mentionStart = -1;
  int _mentionGeneration = 0;

  AttachmentTransferState attachmentState(String messageLocalId) =>
      _attachmentTransferService.stateFor(messageLocalId);

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  List<AiStreamReply> get aiStreamReplies =>
      _aiStreamReplies.values.toList()
        ..sort((a, b) => b.sourceMessageId.compareTo(a.sourceMessageId));
  List<AiRunRecord> get recentAiRuns => List.unmodifiable(_recentAiRuns);
  String get title => friend?.title ?? _title;
  String get peerDisplayName => firstNonEmpty(<Object?>[
    asMap(friend?.raw['destination'])['displayName'],
    asMap(friend?.raw['destination'])['name'],
    title,
  ]);
  String? get peerAvatarUrl =>
      (asMap(friend?.raw['destination'])['thumbnail'] ??
              asMap(friend?.raw['destination'])['portrait'])
          ?.toString();
  int? get peerChatObjectId =>
      asInt(asMap(friend?.raw['destination'])['id']) ??
      asInt(friend?.raw['destinationId']);
  bool get isMuted => friend?.isMuted == true;
  int get destinationObjectType =>
      asInt(asMap(friend?.raw['destination'])['objectType']) ?? 0;
  bool get isOfficialAccount =>
      destinationObjectType == 3 || destinationObjectType == 4;

  List<Map<String, dynamic>> get officialAccountMenus {
    final rawMenus = friend?.raw['menus'];
    if (rawMenus is List && rawMenus.isNotEmpty) {
      return rawMenus.whereType<Map<String, dynamic>>().toList();
    }
    if (isOfficialAccount) {
      return const [
        {'name': '最新资讯', 'type': 'click', 'key': '最新资讯'},
        {
          'name': '服务大厅',
          'subButtons': [
            {'name': '在线客服', 'type': 'click', 'key': '转人工客服'},
            {'name': '业务办理', 'type': 'click', 'key': '业务办理'},
            {'name': '帮助中心', 'type': 'click', 'key': '帮助中心'},
          ],
        },
        {'name': '个人中心', 'type': 'click', 'key': '个人中心'},
      ];
    }
    return const [];
  }

  Uint8List? imagePreview(String localId) => _imagePreviews[localId];

  ChatMessage? messageByServerId(int? serverId) {
    if (serverId == null) return null;
    for (final message in _messages) {
      if (message.serverId == serverId) return message;
    }
    return null;
  }

  Future<ChatMessage?> findLocalMessageByServerId(int? serverId) {
    if (serverId == null) return Future<ChatMessage?>.value(null);
    return _repository.findLocalByServerId(
      ownerId: ownerId,
      sessionUnitId: sessionUnitId,
      serverId: serverId,
    );
  }

  String get mentionKeyword => _mentionKeyword;
  int? get initialUnreadDividerMessageId => _initialUnreadDividerMessageId;

  final Stopwatch _traceStopwatch = Stopwatch();

  Future<void> initialize() async {
    _traceStopwatch.start();
    debugPrint(
      '[ChatTrace] ▶ [1/5] initialize started | session=$sessionUnitId',
    );
    _attachmentTransferService.addListener(_onAttachmentTransferChanged);
    _sessionChangeSubscription = _sessionChangeBus.events.listen((event) {
      if (event.ownerId == ownerId && event.sessionUnitId == sessionUnitId) {
        unawaited(_reloadFromLocalChange());
      }
    });
    _aiStreamSubscription = _aiStreamChangeBus.events.listen(_onAiStreamEvent);
    _signalRSubscription = _signalRGateway.events.listen(_onSignalREvent);
    _restoreAiStreamReplies();

    isLoading = true;
    final localLoadWatch = Stopwatch()..start();
    try {
      final results = await Future.wait([
        _sessionRepository.loadLocalFriendDetail(sessionUnitId),
        _repository.loadInitialLocal(
          ownerId: ownerId,
          sessionUnitId: sessionUnitId,
          limit: initialPageSize,
        ),
      ]);

      final localFriend = results[0] as SessionSummary?;
      final localPage = results[1] as MessagePage;

      if (localFriend != null) {
        friend = localFriend;
        _title = localFriend.title;
      }
      _messages
        ..clear()
        ..addAll(localPage.items);
      _deduplicateMessages();
      _restoreAiStreamReplies();
      hasMore = localPage.hasMore;

      _initialUnreadDividerMessageId = findInitialUnreadDividerMessageId(
        messages: _messages,
        readMessageId: friend?.readMessageId,
      );
      debugPrint(
        '[ChatTrace] ✔ [2/5] local SQLite cache loaded | '
        'cost=${localLoadWatch.elapsedMilliseconds}ms | '
        'totalElapsed=${_traceStopwatch.elapsedMilliseconds}ms | '
        'friend=${friend?.title} | '
        'messagesCount=${_messages.length}',
      );
    } catch (exception) {
      error = exception;
      debugPrint(
        '[ChatTrace] ✖ [2/5] local SQLite cache load failed | '
        'cost=${localLoadWatch.elapsedMilliseconds}ms | '
        'error=$exception',
      );
    } finally {
      isLoading = false;
      notifyListeners();
    }

    if (_messages.isEmpty && hasMore) {
      unawaited(loadMore());
    }

    // Defer background network synchronization until after the page route animation
    unawaited(
      Future.delayed(const Duration(milliseconds: 300), () async {
        debugPrint(
          '[ChatTrace] ⏳ [3/5] deferred network sync triggered | '
          'totalElapsed=${_traceStopwatch.elapsedMilliseconds}ms',
        );
        await _restoreActiveAiRun();
        // The friend detail supplies the authoritative remote destination
        // (AI/contact) and lastMessage. It must follow the local Friend cache
        // directly, before subsequent message/read-state synchronization.
        await _refreshFriendDetail();
        // SignalR may have been disconnected while the AI final message was
        // persisted.  Always run the incremental pull, including for a fresh
        // local cache (cursor = 0), so reopening a conversation cannot lose
        // an offline reply merely because SQLite has no prior message yet.
        final syncWatch = Stopwatch()..start();
        await loadLatest();
        debugPrint(
          '[ChatTrace] ✔ [4/5] latest messages synced | '
          'cost=${syncWatch.elapsedMilliseconds}ms | '
          'totalElapsed=${_traceStopwatch.elapsedMilliseconds}ms',
        );
        // Reading is intentionally last: it must only acknowledge messages
        // after the remote Friend and message payloads are persisted locally.
        await markLatestRead();
      }),
    );
  }

  Future<void> _restoreActiveAiRun() async {
    try {
      final payload = await _sessionRepository.loadActiveAiRun(
        sessionUnitId: sessionUnitId,
      );
      final event = AiStreamEvent.fromRecoveryPayload(payload);
      if (event == null || event.requesterSessionUnitId != sessionUnitId) {
        // The endpoint returns 204 when Redis has no active run. Clear a
        // stale SignalR snapshot so the UI cannot remain on “AI 正在思考”.
        _aiStreamChangeBus.removeForRequesterSessionUnit(sessionUnitId);
        _restoreAiStreamReplies();
        notifyListeners();
        return;
      }
      _aiStreamChangeBus.restore(event);
      _restoreAiStreamReplies();
      notifyListeners();
      debugPrint(
        '[ChatTrace] AI run recovered from Redis | run=${event.runId} status=${event.kind.name}',
      );
    } catch (exception) {
      // Recovery is a reliability enhancement. A temporary API failure must
      // not prevent normal chat history or SignalR from remaining usable.
      debugPrint('[ChatTrace] AI run recovery unavailable | error=$exception');
    }
  }

  Future<void> refreshRecentAiRuns() async {
    try {
      _recentAiRuns = (await _sessionRepository.loadRecentAiRuns(
        sessionUnitId: sessionUnitId,
      )).map(AiRunRecord.fromJson).toList(growable: false);
      notifyListeners();
    } catch (exception) {
      debugPrint('[ChatTrace] AI run history unavailable | error=$exception');
      rethrow;
    }
  }

  void _onAttachmentTransferChanged() {
    notifyListeners();
  }

  Future<void> _refreshFriendDetail() async {
    final watch = Stopwatch()..start();
    try {
      final remote = await _sessionRepository.loadRemoteFriendDetail(
        ownerId: ownerId,
        sessionUnitId: sessionUnitId,
      );
      friend = remote;
      _title = remote.title;
      notifyListeners();
      debugPrint(
        '[ChatTrace] ✔ [5/5] remote friend detail synced | '
        'cost=${watch.elapsedMilliseconds}ms | '
        'totalElapsed=${_traceStopwatch.elapsedMilliseconds}ms | '
        'title=${remote.title}',
      );
    } catch (exception) {
      debugPrint(
        '[ChatTrace] ✖ [5/5] remote friend detail sync failed | '
        'cost=${watch.elapsedMilliseconds}ms | '
        'error=$exception',
      );
    }
  }

  Future<void> loadMore() async {
    if (isLoading || !hasMore) return;
    isLoading = true;
    error = null;
    notifyListeners();
    final watch = Stopwatch()..start();
    try {
      final page = await _repository.loadHistory(
        ownerId: ownerId,
        sessionUnitId: sessionUnitId,
        beforeScore: _messages.isEmpty ? null : _messages.last.score,
        limit: pageSize,
      );
      if (page.items.isEmpty) {
        hasMore = false;
      } else {
        final existingIds = _messages.map((item) => item.localId).toSet();
        for (final item in page.items) {
          if (existingIds.add(item.localId)) {
            _messages.add(item);
          }
        }
        _deduplicateMessages();
        hasMore = page.hasMore;
      }
      debugPrint(
        '[ChatTrace] 📜 loadMore history finished | '
        'cost=${watch.elapsedMilliseconds}ms | '
        'newItems=${page.items.length} | '
        'total=${_messages.length}',
      );
    } catch (exception, stackTrace) {
      error = exception;
      debugPrint(
        '[loadMore][ERROR] session=$sessionUnitId error=$exception\n$stackTrace',
      );
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadLatest() async {
    if (isLoadingLatest) return;
    isLoadingLatest = true;
    // The cursor must come from Drift instead of this controller's temporary
    // page.  A new chat controller is created on re-entry, so only the local
    // database can reliably carry forward the newest persisted server ID.
    try {
      final minMessageId = await _repository.maxLocalServerId(
        ownerId: ownerId,
        sessionUnitId: sessionUnitId,
      );
      final latest = await _repository.loadLatest(
        ownerId: ownerId,
        sessionUnitId: sessionUnitId,
        minMessageId: minMessageId,
      );
      final byId = <String, ChatMessage>{
        for (final item in _messages) item.localId: item,
        for (final item in latest) item.localId: item,
      };
      _messages
        ..clear()
        ..addAll(byId.values);
      _deduplicateMessages();
      _messages.sort((a, b) => b.score.compareTo(a.score));
    } catch (exception) {
      debugPrint(
        '[loadMessages][latest-failed] session=$sessionUnitId error=$exception',
      );
    } finally {
      isLoadingLatest = false;
      notifyListeners();
    }
  }

  Future<void> send(String text) async {
    final value = text.trim();
    if (value.isEmpty || isSending) return;
    if (isMuted) {
      error = StateError('你已被禁言，暂时不能发言');
      notifyListeners();
      return;
    }
    isSending = true;
    notifyListeners();
    final quote = quoting;
    final remindList = _mentionedTokens.entries
        .where((entry) => value.contains(entry.value))
        .map((entry) => entry.key)
        .toList(growable: false);
    quoting = null;
    _mentionedTokens.clear();
    _hideMention();
    final clientMessageId = '${DateTime.now().microsecondsSinceEpoch}';
    final pending = ChatMessage(
      localId: clientMessageId,
      serverId: null,
      clientMessageId: clientMessageId,
      ownerId: ownerId,
      sessionUnitId: sessionUnitId,
      senderSessionUnitId: sessionUnitId,
      messageType: 0,
      state: 'sending',
      score: (_messages.isEmpty ? 0 : _messages.first.score) + 1,
      createdAt: DateTime.now(),
      raw: <String, dynamic>{
        'content': <String, dynamic>{'text': value},
        if (quote?.serverId != null) 'quoteMessageId': quote!.serverId,
        if (quote != null) 'quoteMessage': quote.raw,
      },
    );
    _replaceMessage(pending);
    notifyListeners();
    final sent = await _repository.sendText(
      ownerId: ownerId,
      sessionUnitId: sessionUnitId,
      text: value,
      quote: quote,
      remindList: remindList,
      clientMessageId: clientMessageId,
    );
    _replaceMessage(sent);
    isSending = false;
    notifyListeners();
    _playSentEffect(sent);
  }

  void updateMentionInput(String text) {
    final match = RegExp(r'(?:^|\s)@([^\s@]*)$').firstMatch(text);
    if (match == null) {
      final wasVisible = mentionVisible;
      _hideMention();
      if (wasVisible) notifyListeners();
      return;
    }
    final keyword = match.group(1) ?? '';
    final part = match.group(0) ?? '';
    final start = match.start + (part.startsWith(' ') ? 1 : 0);
    if (mentionVisible &&
        keyword == _mentionKeyword &&
        start == _mentionStart) {
      return;
    }
    mentionVisible = true;
    _mentionKeyword = keyword;
    _mentionStart = start;
    mentionMembers.clear();
    mentionHasMore = true;
    final generation = ++_mentionGeneration;
    unawaited(_loadMentions(generation: generation, reset: true));
    notifyListeners();
  }

  Future<void> loadMoreMentions() =>
      _loadMentions(generation: _mentionGeneration, reset: false);

  void updateMentionKeyword(String keyword) {
    if (!mentionVisible || keyword == _mentionKeyword) return;
    _mentionKeyword = keyword;
    mentionMembers.clear();
    mentionHasMore = true;
    final generation = ++_mentionGeneration;
    unawaited(_loadMentions(generation: generation, reset: true));
    notifyListeners();
  }

  void dismissMention() {
    _hideMention();
    notifyListeners();
  }

  Future<void> _loadMentions({
    required int generation,
    required bool reset,
  }) async {
    if (mentionLoading || (!reset && !mentionHasMore)) return;
    mentionLoading = true;
    notifyListeners();
    try {
      final last = reset || mentionMembers.isEmpty ? null : mentionMembers.last;
      final page = await _chatSettingsRepository.loadMembers(
        ownerId: ownerId,
        sessionUnitId: sessionUnitId,
        cursorScore: last?.score,
        cursorId: last?.id,
        limit: 30,
        keyword: _mentionKeyword,
      );
      if (generation != _mentionGeneration || !mentionVisible) return;
      final existing = mentionMembers.map((member) => member.id).toSet();
      mentionMembers.addAll(
        page.items.where((member) => existing.add(member.id)),
      );
      mentionHasMore = page.hasMore;
      debugPrint(
        '[mention][page] session=$sessionUnitId keyword=$_mentionKeyword '
        'added=${page.items.length} total=${mentionMembers.length} hasMore=${page.hasMore}',
      );
    } catch (exception) {
      if (generation == _mentionGeneration) {
        error = exception;
        debugPrint('[mention][failed] session=$sessionUnitId error=$exception');
      }
    } finally {
      if (generation == _mentionGeneration) {
        mentionLoading = false;
        notifyListeners();
      }
    }
  }

  String insertMention(String text, ChatMember member) {
    if (_mentionStart < 0) return text;
    final prefix = text.substring(0, _mentionStart);
    final suffixStart = _mentionStart + 1 + _mentionKeyword.length;
    final suffix =
        suffixStart <= text.length ? text.substring(suffixStart) : '';
    final token = '@${member.name} ';
    _mentionedTokens[member.id] = token.trimRight();
    _hideMention();
    notifyListeners();
    return '$prefix$token$suffix';
  }

  bool isMemberMentioned(ChatMember member, String text) {
    final token = '@${member.name}';
    return _mentionedTokens[member.id] == token ||
        RegExp('@${RegExp.escape(member.name)}(?=\\s|\$)').hasMatch(text);
  }

  String toggleMention(String text, ChatMember member) {
    final token = '@${member.name}';
    if (isMemberMentioned(member, text)) {
      _mentionedTokens.remove(member.id);
      final value = text
          .replaceAll(RegExp('@${RegExp.escape(member.name)}(?=\\s|\$)'), '')
          .replaceAll(RegExp(r' {2,}'), ' ');
      notifyListeners();
      return value;
    }

    _mentionedTokens[member.id] = token;
    if (_mentionStart >= 0) {
      final prefix = text.substring(0, _mentionStart);
      final suffixStart = _mentionStart + 1 + _mentionKeyword.length;
      final suffix =
          suffixStart <= text.length ? text.substring(suffixStart) : '';
      _mentionStart = -1;
      final value = '$prefix$token $suffix';
      notifyListeners();
      return value;
    }
    final value = '${text.trimRight()} $token ';
    notifyListeners();
    return value;
  }

  void _hideMention() {
    if (!mentionVisible && _mentionStart == -1) return;
    mentionVisible = false;
    mentionLoading = false;
    mentionHasMore = false;
    _mentionStart = -1;
    _mentionKeyword = '';
    _mentionGeneration++;
  }

  Future<void> chooseAndSendFile() async {
    try {
      final files = await _filePickerService.chooseFile(
        const FilePickerRequest(dialogTitle: '选择要发送的文件'),
      );
      if (files.isEmpty) return;
      await _sendFile(files.first);
    } catch (exception) {
      error = exception;
      notifyListeners();
    }
  }

  Future<void> chooseAndSendImages() async {
    try {
      final images = await _mediaService.chooseImage(
        const MediaPickRequest(allowMultiple: true, maxCount: 9),
      );
      for (final image in images) {
        final local = await _repository.createLocalImage(
          ownerId: ownerId,
          sessionUnitId: sessionUnitId,
          file: image,
        );
        _pendingFiles[local.localId] = image;
        _imagePreviews[local.localId] = await image.readBytes();
        _replaceMessage(local);
        notifyListeners();
        uploadProgress[local.localId] = 0;
        final sent = await _repository.sendLocalImage(
          local: local,
          file: image,
          onProgress: (sent, total) {
            uploadProgress[local.localId] = total <= 0 ? 0 : sent / total;
            notifyListeners();
          },
        );
        _replaceMessage(sent);
        if (sent.state == 'sent') _pendingFiles.remove(local.localId);
        uploadProgress.remove(local.localId);
        notifyListeners();
        _playSentEffect(sent);
      }
    } catch (exception) {
      error = exception;
      notifyListeners();
    }
  }

  Future<void> takeAndSendPhoto() async {
    final image = await _mediaService.takePhoto(const MediaPickRequest());
    if (image != null) await _sendImage(image);
  }

  Future<void> chooseAndSendVideo() async {
    final video = await _mediaService.chooseVideo(
      const MediaPickRequest(maxDuration: Duration(minutes: 10)),
    );
    if (video != null) await _sendVideo(video);
  }

  Future<void> recordAndSendVideo() async {
    final video = await _mediaService.recordVideo(
      const MediaPickRequest(maxDuration: Duration(minutes: 10)),
    );
    if (video != null) await _sendVideo(video);
  }

  Future<void> _sendImage(SelectedFile image) async {
    final local = await _repository.createLocalImage(
      ownerId: ownerId,
      sessionUnitId: sessionUnitId,
      file: image,
    );
    _pendingFiles[local.localId] = image;
    _imagePreviews[local.localId] = await image.readBytes();
    _replaceMessage(local);
    notifyListeners();
    uploadProgress[local.localId] = 0;
    final sent = await _repository.sendLocalImage(
      local: local,
      file: image,
      onProgress: (sent, total) {
        uploadProgress[local.localId] = total <= 0 ? 0 : sent / total;
        notifyListeners();
      },
    );
    _replaceMessage(sent);
    uploadProgress.remove(local.localId);
    if (sent.state == 'sent') _pendingFiles.remove(local.localId);
    notifyListeners();
    _playSentEffect(sent);
  }

  Future<void> _sendVideo(SelectedFile video) async {
    final local = await _repository.createLocalVideo(
      ownerId: ownerId,
      sessionUnitId: sessionUnitId,
      file: video,
    );
    _pendingFiles[local.localId] = video;
    _replaceMessage(local);
    uploadProgress[local.localId] = 0;
    notifyListeners();
    final sent = await _repository.sendLocalVideo(
      local: local,
      file: video,
      onProgress: (sent, total) {
        uploadProgress[local.localId] = total <= 0 ? 0 : sent / total;
        notifyListeners();
      },
    );
    _replaceMessage(sent);
    uploadProgress.remove(local.localId);
    if (sent.state == 'sent') _pendingFiles.remove(local.localId);
    notifyListeners();
    _playSentEffect(sent);
  }

  void quoteMessage(ChatMessage message) {
    if (message.serverId == null) return;
    quoting = message;
    selectionMode = false;
    selectedLocalIds.clear();
    notifyListeners();
  }

  void cancelQuote() {
    quoting = null;
    notifyListeners();
  }

  Future<void> copyMessage(ChatMessage message) =>
      _clipboardService.copy(message.text);

  Future<void> copyLink(ChatMessage message) =>
      _clipboardService.copy(message.linkUrl);

  void beginSelection(ChatMessage message) {
    selectionMode = true;
    selectedLocalIds.add(message.localId);
    notifyListeners();
  }

  void toggleSelection(ChatMessage message) {
    if (!selectionMode) return;
    if (!selectedLocalIds.add(message.localId)) {
      selectedLocalIds.remove(message.localId);
    }
    notifyListeners();
  }

  void cancelSelection() {
    selectionMode = false;
    selectedLocalIds.clear();
    notifyListeners();
  }

  Future<void> deleteMessages(Iterable<String> localIds) async {
    final ids = localIds.toSet();
    if (ids.isEmpty) return;
    await _repository.deleteLocal(ids);
    _messages.removeWhere((message) => ids.contains(message.localId));
    cancelSelection();
  }

  Future<void> deleteSelectedMessages() async {
    final selected = _messages
        .where((message) => selectedLocalIds.contains(message.localId))
        .toList(growable: false);
    if (selected.isEmpty) return;
    for (final message in selected) {
      if (message.serverId == null) {
        await _repository.deleteLocal(<String>[message.localId]);
      } else {
        await _repository.deleteRemote(message);
      }
    }
    _messages.removeWhere(
      (message) => selectedLocalIds.contains(message.localId),
    );
    cancelSelection();
  }

  Future<void> deleteRemote(ChatMessage message) async {
    await _repository.deleteRemote(message);
    _messages.removeWhere((item) => item.localId == message.localId);
    notifyListeners();
  }

  Future<void> rollbackMessage(ChatMessage message) async {
    final updated = await _repository.rollback(message);
    _replaceMessage(updated);
    notifyListeners();
  }

  Future<List<SessionSummary>> loadForwardTargets() async =>
      (await _sessionRepository.loadFriends(ownerId: ownerId, limit: 100)).items
          .where((item) => item.id != sessionUnitId)
          .toList(growable: false);

  Future<void> forwardMessage(
    ChatMessage message,
    String targetSessionUnitId,
  ) async {
    await _repository.forward(
      message: message,
      targetSessionUnitIds: <String>[targetSessionUnitId],
    );
  }

  Future<void> forwardSelectedAsHistory(String targetSessionUnitId) async {
    final selected = _messages
        .where((message) => selectedLocalIds.contains(message.localId))
        .toList(growable: false);
    if (selected.any((message) => message.serverId == null)) {
      throw StateError('请等待所选消息发送完成后再合并转发');
    }
    final ids = selected
        .map((message) => message.serverId!)
        .toList(growable: false);
    await _repository.forwardHistory(
      targetSessionUnitId: targetSessionUnitId,
      messageIds: ids,
    );
    cancelSelection();
  }

  Future<void> markLatestRead() async {
    final messageId = _messages
        .where((item) => !item.isMine && item.serverId != null)
        .map((item) => item.serverId!)
        .fold<int>(0, (max, id) => id > max ? id : max);
    if (messageId <= 0) return;
    if (_lastSubmittedReadMessageId != null &&
        _lastSubmittedReadMessageId! >= messageId) {
      return;
    }
    if (friend?.readMessageId != null && friend!.readMessageId! >= messageId) {
      _lastSubmittedReadMessageId = friend!.readMessageId;
      return;
    }
    _lastSubmittedReadMessageId = messageId;
    newMessageCount = 0;
    try {
      friend = await _repository.setRead(
        ownerId: ownerId,
        sessionUnitId: sessionUnitId,
        messageId: messageId,
      );
      notifyListeners();
    } catch (exception) {
      debugPrint(
        '[setRead][failed] session=$sessionUnitId messageId=$messageId error=$exception',
      );
      if (_lastSubmittedReadMessageId == messageId) {
        _lastSubmittedReadMessageId = null;
      }
    }
  }

  void clearNewMessageCount() {
    newMessageCount = 0;
    notifyListeners();
    unawaited(markLatestRead());
  }

  void setViewingLatest(bool value) {
    if (_viewingLatest == value) return;
    _viewingLatest = value;
    if (value) clearNewMessageCount();
  }

  Future<void> _reloadFromLocalChange() async {
    final latest = await _repository.loadLocalLatest(
      ownerId: ownerId,
      sessionUnitId: sessionUnitId,
    );
    var receivedIncoming = false;
    for (final message in latest) {
      final known = _messages.any(
        (item) =>
            item.localId == message.localId ||
            (item.serverId != null && item.serverId == message.serverId),
      );
      if (!known && !message.isMine) receivedIncoming = true;
      _replaceMessage(message);
      if (message.quoteMessageId != null) {
        _aiStreamReplies.remove(message.quoteMessageId);
        _aiStreamChangeBus.removeBySourceMessageId(message.quoteMessageId!);
      }
    }
    if (receivedIncoming && !_viewingLatest) newMessageCount++;
    notifyListeners();
    if (receivedIncoming && _viewingLatest) unawaited(markLatestRead());
  }

  Future<void> startVoiceRecording() => _mediaService.startAudioRecording(
    const AudioRecordingRequest(fileNamePrefix: 'gotoim_voice'),
  );

  Future<bool> hasVoiceRecordingPermission() =>
      _mediaService.hasAudioRecordingPermission();

  Future<double> voiceRecordingLevel() => _mediaService.audioRecordingLevel();

  Stream<double> voiceRecordingLevels(Duration interval) =>
      _mediaService.audioRecordingLevels(interval);

  Future<void> cancelVoiceRecording() => _mediaService.cancelAudioRecording();

  Future<void> finishVoiceRecording(Duration duration) async {
    final file = await _mediaService.stopAudioRecording();
    if (file == null) return;
    final local = await _repository.createLocalVoice(
      ownerId: ownerId,
      sessionUnitId: sessionUnitId,
      file: file,
      duration: duration,
    );
    _pendingFiles[local.localId] = file;
    _replaceMessage(local);
    notifyListeners();
    final sent = await _repository.sendLocalVoice(
      local: local,
      file: file,
      duration: duration,
    );
    _replaceMessage(sent);
    if (sent.state == 'sent') _pendingFiles.remove(local.localId);
    notifyListeners();
    _playSentEffect(sent);
  }

  Future<void> _sendFile(SelectedFile file) async {
    final local = await _repository.createLocalFile(
      ownerId: ownerId,
      sessionUnitId: sessionUnitId,
      file: file,
    );
    _pendingFiles[local.localId] = file;
    _replaceMessage(local);
    notifyListeners();

    final sent = await _repository.sendLocalFile(local: local, file: file);
    _replaceMessage(sent);
    if (sent.state == 'sent') _pendingFiles.remove(local.localId);
    notifyListeners();
    _playSentEffect(sent);
  }

  Future<void> retryFile(ChatMessage message) async {
    final file = _pendingFiles[message.localId];
    if (file == null || message.state == 'sending') return;
    final sending = message.copyWith(state: 'sending');
    _replaceMessage(sending);
    notifyListeners();
    final sent =
        message.messageType == 3
            ? await _repository.sendLocalVoice(local: sending, file: file)
            : message.messageType == 2
            ? await _repository.sendLocalImage(local: sending, file: file)
            : message.messageType == 4
            ? await _repository.sendLocalVideo(local: sending, file: file)
            : await _repository.sendLocalFile(local: sending, file: file);
    _replaceMessage(sent);
    if (sent.state == 'sent') _pendingFiles.remove(message.localId);
    notifyListeners();
    _playSentEffect(sent);
  }

  Future<void> retryMessage(ChatMessage message) async {
    if (message.state != 'failed') return;
    if (message.messageType != 0) {
      await retryFile(message);
      return;
    }
    final retried = await _repository.retryText(message);
    _replaceMessage(retried);
    notifyListeners();
    _playSentEffect(retried);
  }

  bool canRetryMessage(ChatMessage message) =>
      message.state == 'failed' &&
      (message.messageType == 0 || _pendingFiles.containsKey(message.localId));

  String _attachmentSource(ChatMessage message) =>
      message.mediaUrl ?? message.audioUrl ?? message.linkUrl;

  Future<void> downloadAttachment(ChatMessage message) =>
      _attachmentTransferService.download(
        id: message.localId,
        source: _attachmentSource(message),
        fileName: message.fileName.isEmpty ? '附件' : message.fileName,
        userId: ownerId.toString(),
        chatTarget: sessionUnitId,
        messageDate: message.createdAt,
        category: resolveAttachmentCategory(
          message.fileName,
          fileSuffix: message.fileSuffix,
          messageType: message.messageType,
        ),
      );

  Future<void> cancelAttachmentDownload(ChatMessage message) =>
      _attachmentTransferService.cancel(message.localId);

  Future<void> openAttachment(ChatMessage message) =>
      _attachmentTransferService.open(
        id: message.localId,
        source: _attachmentSource(message),
        fileName: message.fileName.isEmpty ? '附件' : message.fileName,
        userId: ownerId.toString(),
        chatTarget: sessionUnitId,
        messageDate: message.createdAt,
        category: resolveAttachmentCategory(
          message.fileName,
          fileSuffix: message.fileSuffix,
          messageType: message.messageType,
        ),
      );

  Future<void> saveAttachmentAs(ChatMessage message) =>
      _attachmentTransferService.saveAs(
        id: message.localId,
        source: _attachmentSource(message),
        fileName: message.fileName.isEmpty ? '附件' : message.fileName,
        userId: ownerId.toString(),
        chatTarget: sessionUnitId,
        messageDate: message.createdAt,
        category: resolveAttachmentCategory(
          message.fileName,
          fileSuffix: message.fileSuffix,
          messageType: message.messageType,
        ),
        mimeType: message.content['contentType']?.toString(),
      );

  void _playSentEffect(ChatMessage message) {
    if (message.state == 'sent') {
      unawaited(_audioPlaybackService.playSendEffect());
    }
  }

  Future<void> markVoiceOpened(ChatMessage message) async {
    if (message.isOpened || message.isMine) return;
    final updated = message.copyWith(
      raw: <String, dynamic>{...message.raw, 'isOpened': true},
    );
    final index = _messages.indexWhere(
      (item) => item.localId == message.localId,
    );
    if (index >= 0) {
      _messages[index] = updated;
      notifyListeners();
    }
    await _repository.markOpened(message.localId);
  }

  void _replaceMessage(ChatMessage value) {
    final index = _messages.indexWhere(
      (message) =>
          message.localId == value.localId ||
          (value.serverId != null && message.serverId == value.serverId) ||
          (value.clientMessageId != null &&
              value.clientMessageId!.trim().isNotEmpty &&
              message.clientMessageId == value.clientMessageId),
    );
    if (index < 0) {
      _messages.insert(0, value);
    } else {
      _messages[index] = value;
    }
    _deduplicateMessages();
    _messages.sort((a, b) => b.score.compareTo(a.score));
  }

  void _deduplicateMessages() {
    final seenLocalIds = <String>{};
    final seenServerIds = <int>{};
    final seenClientIds = <String>{};
    _messages.removeWhere((item) {
      if (!seenLocalIds.add(item.localId)) return true;
      if (item.serverId != null && !seenServerIds.add(item.serverId!)) {
        return true;
      }
      final clientMsgId = item.clientMessageId?.trim();
      if (clientMsgId != null &&
          clientMsgId.isNotEmpty &&
          !seenClientIds.add(clientMsgId)) {
        return true;
      }
      return false;
    });
  }

  void handleMessagesCleared() {
    _messages.clear();
    _initialUnreadDividerMessageId = null;
    _timeVisibilityResetMarker++;
    hasMore = true;
    error = null;
    isLoading = false;
    isLoadingLatest = false;
    notifyListeners();
  }

  int _timeVisibilityResetMarker = 0;
  int get timeVisibilityResetMarker => _timeVisibilityResetMarker;

  @override
  void dispose() {
    _attachmentTransferService.removeListener(_onAttachmentTransferChanged);
    unawaited(_sessionChangeSubscription?.cancel());
    unawaited(_aiStreamSubscription?.cancel());
    unawaited(_signalRSubscription?.cancel());
    _aiStreamElapsedTimer?.cancel();
    _aiRunRecoveryTimer?.cancel();
    super.dispose();
  }

  void _onAiStreamEvent(AiStreamEvent event) {
    if (event.requesterSessionUnitId != sessionUnitId) return;
    _restoreAiStreamReplies();
    _syncAiStreamElapsedTimer();
    _syncAiRunRecoveryPolling();
    notifyListeners();
  }

  void _onSignalREvent(SignalRAppEvent event) {
    if (event is! SignalRConnectionEvent) return;
    if (event.state == SignalRConnectionState.connected) {
      _aiRunRecoveryTimer?.cancel();
      _aiRunRecoveryTimer = null;
      unawaited(_recoverAfterSignalRReconnect());
      return;
    }
    _syncAiRunRecoveryPolling();
  }

  /// SignalR is a fast path, not the source of truth. Once transport returns,
  /// replay the durable state in the same safe order used when entering chat.
  /// This covers a reply that was persisted while the app was backgrounded.
  Future<void> _recoverAfterSignalRReconnect() async {
    if (_isRecoveringAfterRealtimeReconnect) return;
    _isRecoveringAfterRealtimeReconnect = true;
    final watch = Stopwatch()..start();
    try {
      await _restoreActiveAiRun();
      await _refreshFriendDetail();
      await loadLatest();
      await markLatestRead();
      debugPrint(
        '[ChatTrace] SignalR reconnect durable recovery complete | '
        'session=$sessionUnitId cost=${watch.elapsedMilliseconds}ms',
      );
    } catch (exception) {
      // Every sub-operation is already best-effort, but keep this boundary so
      // a future recovery step can never crash the SignalR subscription.
      debugPrint(
        '[ChatTrace] SignalR reconnect durable recovery failed | '
        'session=$sessionUnitId error=$exception',
      );
    } finally {
      _isRecoveringAfterRealtimeReconnect = false;
    }
  }

  void _restoreAiStreamReplies() {
    final persistedSourceMessageIds =
        _messages
            .map((message) => message.quoteMessageId)
            .whereType<int>()
            .toSet();
    for (final sourceMessageId in persistedSourceMessageIds) {
      _aiStreamChangeBus.removeBySourceMessageId(sourceMessageId);
    }
    _aiStreamReplies
      ..clear()
      ..addEntries(
        _aiStreamChangeBus
            .activeForRequesterSessionUnit(sessionUnitId)
            .where(
              (item) =>
                  !persistedSourceMessageIds.contains(item.sourceMessageId),
            )
            .map(
              (item) => MapEntry(
                item.sourceMessageId,
                AiStreamReply.fromSnapshot(item),
              ),
            ),
      );
    _syncAiStreamElapsedTimer();
    _syncAiRunRecoveryPolling();
  }

  void _syncAiStreamElapsedTimer() {
    final hasLiveRun = _aiStreamReplies.values.any(
      (reply) =>
          reply.status == AiStreamStatus.thinking ||
          reply.status == AiStreamStatus.streaming,
    );
    if (!hasLiveRun) {
      _aiStreamElapsedTimer?.cancel();
      _aiStreamElapsedTimer = null;
      return;
    }
    _aiStreamElapsedTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      notifyListeners();
    });
  }

  void _syncAiRunRecoveryPolling() {
    final hasLiveRun = _aiStreamReplies.values.any(
      (reply) =>
          reply.status == AiStreamStatus.thinking ||
          reply.status == AiStreamStatus.streaming,
    );
    final needsPolling =
        hasLiveRun &&
        _signalRGateway.connectionState != SignalRConnectionState.connected;
    if (!needsPolling) {
      _aiRunRecoveryTimer?.cancel();
      _aiRunRecoveryTimer = null;
      return;
    }
    _aiRunRecoveryTimer ??= Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_restoreActiveAiRun()),
    );
  }
}

class AiStreamReply {
  const AiStreamReply({
    required this.runId,
    required this.sourceMessageId,
    required this.sequence,
    required this.status,
    this.text = '',
    this.error = '',
    this.startedAt,
    this.queueMilliseconds = 0,
    this.elapsedMilliseconds = 0,
  });

  final String runId;
  final int sourceMessageId;
  final int sequence;
  final AiStreamStatus status;
  final String text;
  final String error;
  final DateTime? startedAt;
  final int queueMilliseconds;
  final int elapsedMilliseconds;

  factory AiStreamReply.fromSnapshot(AiStreamSnapshot snapshot) =>
      AiStreamReply(
        runId: snapshot.runId,
        sourceMessageId: snapshot.sourceMessageId,
        sequence: snapshot.sequence,
        status: snapshot.status,
        text: snapshot.text,
        error: snapshot.error,
        startedAt: snapshot.startedAt,
        queueMilliseconds: snapshot.queueMilliseconds,
        elapsedMilliseconds: snapshot.elapsedMilliseconds,
      );

  int displayElapsedMilliseconds(DateTime now) {
    final live =
        status == AiStreamStatus.thinking || status == AiStreamStatus.streaming;
    if (!live || startedAt == null) return elapsedMilliseconds;
    return now.toUtc().difference(startedAt!).inMilliseconds >
            elapsedMilliseconds
        ? now.toUtc().difference(startedAt!).inMilliseconds
        : elapsedMilliseconds;
  }

  AiStreamReply copyWith({int? sequence, AiStreamStatus? status}) =>
      AiStreamReply(
        runId: runId,
        sourceMessageId: sourceMessageId,
        sequence: sequence ?? this.sequence,
        status: status ?? this.status,
        text: text,
        error: error,
        startedAt: startedAt,
        queueMilliseconds: queueMilliseconds,
        elapsedMilliseconds: elapsedMilliseconds,
      );
}
