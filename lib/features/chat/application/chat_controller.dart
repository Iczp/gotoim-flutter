import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import '../../../app/application_providers.dart';
import '../../../core/config/app_environment.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/realtime/signalr_gateway.dart';
import '../../../core/realtime/typing_indicator_service.dart';
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
import '../../chat_settings/data/datasources/chat_member_dao.dart';
import '../../chat_settings/data/models/chat_member.dart';
import '../../chat_settings/data/repositories/chat_settings_repository.dart';
import '../presentation/widgets/chat_composer_controller.dart';

final messageRepositoryProvider = Provider<MessageRepository>((ref) {
  final currentUserId = ref.watch(currentUserProvider.select((user) => user?.id));
  final repository = MessageRepository(
    api: MessageApi(
      ref.watch(apiClientProvider),
      accountScope: currentUserId,
    ),
    dao: MessageDao(
      ref.watch(unifiedDatabaseProvider),
      syncNamespace: ref.watch(appEnvironmentProvider).apiBaseUrl,
    ),
    sessionDao: SessionDao(ref.watch(unifiedDatabaseProvider)),
    memberDao: ChatMemberDao(ref.watch(unifiedDatabaseProvider)),
    sessionChangeBus: ref.watch(sessionChangeBusProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});

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
        cache: ref.watch(attachmentCacheProvider),
      );
    });

class ChatController extends ChangeNotifier implements ChatComposerController {
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
       _title = initialTitle {
    _typingService.addListener(notifyListeners);
  }
  static const pageSize = 30;
  static const initialPageSize = 10;
  final TypingIndicatorService _typingService = TypingIndicatorService();
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
  int get effectiveOwnerId => ownerId > 0 ? ownerId : (friend?.ownerId ?? 0);
  final List<ChatMessage> _messages = <ChatMessage>[];
  final Set<String> _liveAnimatedMessageIds = <String>{};
  final Map<String, SelectedFile> _pendingFiles = <String, SelectedFile>{};
  final Map<String, Uint8List> _imagePreviews = <String, Uint8List>{};
  final Map<String, double> uploadProgress = <String, double>{};
  bool isLoading = false;
  @override
  bool isSending = false;
  bool isLoadingLatest = false;
  bool hasMore = true;
  Object? error;

  bool shouldAnimateMessage(String localId) =>
      _liveAnimatedMessageIds.contains(localId);

  void markMessageAnimated(String localId) {
    _liveAnimatedMessageIds.remove(localId);
  }

  void _markLiveMessageForAnimation(String localId) {
    _liveAnimatedMessageIds.add(localId);
  }

  SessionSummary? friend;
  String _title;
  StreamSubscription<SessionChangeEvent>? _sessionChangeSubscription;
  StreamSubscription<AiStreamEvent>? _aiStreamSubscription;
  StreamSubscription<SignalRAppEvent>? _signalRSubscription;
  Timer? _aiStreamElapsedTimer;
  Timer? _aiRunRecoveryTimer;
  bool _isRecoveringAfterRealtimeReconnect = false;
  bool _isDisposed = false;
  bool _initialized = false;
  final Set<int> _deletedMessageIds = {};
  bool get isDisposed => _isDisposed;

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  final Map<int, AiStreamReply> _aiStreamReplies = <int, AiStreamReply>{};
  List<AiRunRecord> _recentAiRuns = const <AiRunRecord>[];
  @override
  ChatMessage? quoting;
  bool selectionMode = false;
  int newMessageCount = 0;
  bool _viewingLatest = true;
  int? _lastSubmittedReadMessageId;
  int? _initialUnreadDividerMessageId;
  final Set<String> selectedLocalIds = <String>{};
  @override
  final List<ChatMember> mentionMembers = <ChatMember>[];
  final Map<String, String> _mentionedTokens = <String, String>{};
  @override
  bool mentionVisible = false;
  @override
  bool mentionLoading = false;
  @override
  bool mentionHasMore = false;
  String _mentionKeyword = '';
  int _mentionStart = -1;
  int _mentionGeneration = 0;

  AttachmentTransferState attachmentState(String messageLocalId) =>
      _attachmentTransferService.stateFor(messageLocalId);

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  List<AiStreamReply> get aiStreamReplies => _visibleAiStreamReplies();

  /// A chat can receive stale/retried `started@ai` events for older source
  /// messages. The message list has one inline AI placeholder, so render only
  /// the newest live run; the complete run history remains available from the
  /// AI-run timeline.
  List<AiStreamReply> _visibleAiStreamReplies() {
    final replies = _aiStreamReplies.values.toList();
    final liveReplies =
        replies
            .where(
              (reply) =>
                  reply.status == AiStreamStatus.thinking ||
                  reply.status == AiStreamStatus.streaming,
            )
            .toList();
    if (liveReplies.length > 1) {
      liveReplies.sort(
        (left, right) => right.sourceMessageId.compareTo(left.sourceMessageId),
      );
      final newestLiveRunId = liveReplies.first.runId;
      replies.removeWhere(
        (reply) =>
            (reply.status == AiStreamStatus.thinking ||
                reply.status == AiStreamStatus.streaming) &&
            reply.runId != newestLiveRunId,
      );
    }
    replies.sort((a, b) => b.sourceMessageId.compareTo(a.sourceMessageId));
    return List.unmodifiable(replies);
  }

  bool get hasActiveAiStream => _aiStreamReplies.values.any(
    (reply) =>
        reply.status == AiStreamStatus.thinking ||
        reply.status == AiStreamStatus.streaming,
  );

  AiStreamReply? get activeAiStreamReply {
    final live =
        _aiStreamReplies.values
            .where(
              (reply) =>
                  reply.status == AiStreamStatus.thinking ||
                  reply.status == AiStreamStatus.streaming,
            )
            .toList();
    if (live.isEmpty) return null;
    live.sort((a, b) => b.sourceMessageId.compareTo(a.sourceMessageId));
    return live.first;
  }

  List<AiRunRecord> get recentAiRuns => List.unmodifiable(_recentAiRuns);
  String get title => friend?.title ?? _title;
  String? get typingText {
    final sId = friend?.sessionId ?? sessionUnitId;
    final text = _typingService.getTypingText(
      sId,
      isDirect: !(friend?.isGroup ?? false),
    );
    return text.isEmpty ? null : text;
  }

  void _reportTyping(
    bool isTyping, {
    String action = 'typing',
    String? actionText,
  }) {
    final sId = friend?.sessionId ?? sessionUnitId;
    if (sId.isEmpty) return;
    unawaited(
      _typingService.reportTyping(
        messageApi: _repository.api,
        gateway: _signalRGateway,
        sessionId: sId,
        senderSessionUnitId: sessionUnitId,
        senderName: '我',
        isTyping: isTyping,
        action: action,
        actionText: actionText,
      ),
    );
  }
  String get peerDisplayName => firstNonEmpty(<Object?>[
    asMap(friend?.raw['destination'])['displayName'],
    asMap(friend?.raw['destination'])['name'],
    title,
  ]);
  String? get peerAvatarUrl {
    final destination = asMap(
      friend?.raw['destination'] ?? friend?.raw['Destination'],
    );
    final value = firstNonEmpty([
      destination['thumbnail'],
      destination['Thumbnail'],
      destination['portrait'],
      destination['Portrait'],
    ]);
    return value.isEmpty ? null : value;
  }

  String? get myAvatarUrl {
    final owner = asMap(friend?.raw['owner'] ?? friend?.raw['Owner']);
    final value = firstNonEmpty(<Object?>[
      owner['thumbnail'],
      owner['Thumbnail'],
      owner['portrait'],
      owner['Portrait'],
    ]);
    return value.isEmpty ? null : value;
  }

  int? get peerChatObjectId =>
      asInt(asMap(friend?.raw['destination'])['id']) ??
      asInt(friend?.raw['destinationId']);
  @override
  bool get isMuted => friend?.isMuted == true;
  bool get isSessionKilled => friend?.isKilled == true;
  String get activeSessionId => friend?.sessionId ?? sessionUnitId;
  bool get isGroupSession => friend?.isGroup == true;
  String? get backgroundImage {
    final setting = asMap(friend?.raw['setting'] ?? friend?.raw['Setting']);
    return (setting['backgroundImage'] ?? setting['BackgroundImage'])
        ?.toString();
  }

  int get destinationObjectType =>
      asInt(asMap(friend?.raw['destination'])['objectType']) ?? 0;
  @override
  bool get isOfficialAccount =>
      destinationObjectType == 3 || destinationObjectType == 4;

  List<Map<String, dynamic>> _remoteOfficialMenus = const [];
  String? _officialMenuVersion;

  Future<void> _loadOfficialMenus() async {
    if (!isOfficialAccount) return;
    final dest = asMap(friend?.raw['destination']);
    final destId = asInt(dest['id']);
    if (destId == null || destId <= 0) return;
    try {
      final res = await _repository.getPublishedOfficialMenus(
        destId,
        version: _officialMenuVersion,
      );
      if (res != null && !_isDisposed) {
        final isModified = res['isModified'] as bool? ?? true;
        final newVersion = res['version']?.toString();
        if (newVersion != null) {
          _officialMenuVersion = newVersion;
        }
        if (isModified) {
          final items = res['items'];
          if (items is List) {
            _remoteOfficialMenus = items.whereType<Map<String, dynamic>>().toList();
            notifyListeners();
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to load official menus: $e');
    }
  }

  @override
  Future<void> triggerOfficialMenu(Map<String, dynamic> item) async {
    final menuId = item['id']?.toString();
    final eventType = item['type']?.toString().toLowerCase();

    // 针对 View / 网页跳转等非 trigger 动作，执行独立埋点上报
    if (menuId != null && menuId.isNotEmpty && (eventType == 'view' || eventType == 'navigation')) {
      void reportClick() async {
        try {
          await _repository.reportMenuClick(
            menuId: menuId,
            sessionUnitId: sessionUnitId,
            senderId: effectiveOwnerId > 0 ? effectiveOwnerId : null,
          );
        } catch (_) {}
      }
      reportClick();
      return;
    }

    if (menuId != null && menuId.isNotEmpty) {
      try {
        await _repository.triggerOfficialMenu(
          menuId: menuId,
          sessionUnitId: sessionUnitId,
        );
        return;
      } catch (e) {
        debugPrint('triggerOfficialMenu API failed: $e');
      }
    }
    final keyOrName = item['key'] ?? item['name'] ?? '';
    if (keyOrName.toString().isNotEmpty) {
      send(keyOrName.toString());
    }
  }

  @override
  List<Map<String, dynamic>> get officialAccountMenus {
    if (_remoteOfficialMenus.isNotEmpty) {
      return _remoteOfficialMenus;
    }
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

  @override
  String get mentionKeyword => _mentionKeyword;
  int? get initialUnreadDividerMessageId => _initialUnreadDividerMessageId;

  final Stopwatch _traceStopwatch = Stopwatch();

  Future<void> initialize() async {
    if (_initialized || _isDisposed) return;
    _initialized = true;
    _traceStopwatch.start();
    debugPrint(
      '[ChatTrace] ▶ [1/5] initialize started | session=$sessionUnitId',
    );
    _attachmentTransferService.addListener(_onAttachmentTransferChanged);
    _sessionChangeSubscription = _sessionChangeBus.events.listen((event) {
      if (event.ownerId == effectiveOwnerId &&
          event.sessionUnitId == sessionUnitId) {
        _deletedMessageIds.addAll(event.deletedMessageIds ?? const []);
        if (_deletedMessageIds.contains(quoting?.serverId)) quoting = null;
        _messages.removeWhere(
          (message) => _deletedMessageIds.contains(message.serverId),
        );
        selectedLocalIds.removeWhere(
          (id) => !_messages.any((message) => message.localId == id),
        );
        unawaited(
          _reloadFromLocalChange(
            messageId: event.messageId,
            messageIds: event.messageIds,
          ),
        );
      }
    });
    _aiStreamSubscription = _aiStreamChangeBus.events.listen(_onAiStreamEvent);
    _signalRSubscription = _signalRGateway.events.listen(_onSignalREvent);
    _restoreAiStreamReplies();

    isLoading = true;
    final localLoadWatch = Stopwatch()..start();
    var hasLocalMessages = false;
    try {
      final results = await Future.wait([
        _sessionRepository.loadLocalFriendDetail(sessionUnitId),
        _repository.loadInitialLocal(
          ownerId: effectiveOwnerId,
          sessionUnitId: sessionUnitId,
          limit: initialPageSize,
        ),
      ]);

      final localFriend = results[0] as SessionSummary?;
      final localPage = results[1] as MessagePage;

      if (localFriend != null) {
        friend = localFriend;
        _title = localFriend.title;
        if (isOfficialAccount) unawaited(_loadOfficialMenus());
      }
      _messages
        ..clear()
        ..addAll(localPage.items);
      _deduplicateMessages();
      _restoreAiStreamReplies();
      hasMore = localPage.hasMore;
      hasLocalMessages = _messages.isNotEmpty;

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
    }

    if (_isDisposed) return;

    if (hasLocalMessages) {
      isLoading = false;
      notifyListeners();
    } else {
      final remoteWatch = Stopwatch()..start();
      debugPrint(
        '[ChatTrace] 🚀 local cache empty, pulling remote messages immediately | '
        'totalElapsed=${_traceStopwatch.elapsedMilliseconds}ms',
      );
      try {
        final remotePage = await _repository.loadHistory(
          ownerId: effectiveOwnerId,
          sessionUnitId: sessionUnitId,
          beforeScore: null,
          limit: initialPageSize,
        );
        if (_isDisposed) return;
        _messages
          ..clear()
          ..addAll(remotePage.items);
        _deduplicateMessages();
        _restoreAiStreamReplies();
        hasMore = remotePage.hasMore;
        _initialUnreadDividerMessageId = findInitialUnreadDividerMessageId(
          messages: _messages,
          readMessageId: friend?.readMessageId,
        );
        debugPrint(
          '[ChatTrace] ✔ initial remote messages loaded | '
          'cost=${remoteWatch.elapsedMilliseconds}ms | '
          'count=${_messages.length}',
        );
      } catch (remoteError) {
        if (_isDisposed) return;
        error = remoteError;
        debugPrint(
          '[ChatTrace] ✖ initial remote messages load failed | '
          'cost=${remoteWatch.elapsedMilliseconds}ms | '
          'error=$remoteError',
        );
      } finally {
        if (!_isDisposed) {
          isLoading = false;
          notifyListeners();
        }
      }
    }

    if (_isDisposed) return;

    // Defer background network synchronization until after the page route animation
    unawaited(
      Future.delayed(
        hasLocalMessages ? const Duration(milliseconds: 300) : Duration.zero,
        () async {
          if (_isDisposed) return;
          debugPrint(
            '[ChatTrace] ⏳ [3/5] deferred network sync triggered | '
            'totalElapsed=${_traceStopwatch.elapsedMilliseconds}ms',
          );
          await _restoreActiveAiRun();
          if (_isDisposed) return;
          // The friend detail supplies the authoritative remote destination
          // (AI/contact) and lastMessage. It must follow the local Friend cache
          // directly, before subsequent message/read-state synchronization.
          await _refreshFriendDetail();
          if (_isDisposed) return;
          // SignalR may have been disconnected while the AI final message was
          // persisted.  Always run the incremental pull, including for a fresh
          // local cache (cursor = 0), so reopening a conversation cannot lose
          // an offline reply merely because SQLite has no prior message yet.
          final syncWatch = Stopwatch()..start();
          await loadLatest(refreshRecent: true);
          if (_isDisposed) return;
          debugPrint(
            '[ChatTrace] ✔ [4/5] latest messages synced | '
            'cost=${syncWatch.elapsedMilliseconds}ms | '
            'totalElapsed=${_traceStopwatch.elapsedMilliseconds}ms',
          );
          // Reading is intentionally last: it must only acknowledge messages
          // after the remote Friend and message payloads are persisted locally.
          await markLatestRead();
        },
      ),
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

  /// Immediately stops the thinking/streaming state in the local UI
  /// and notifies the backend to cancel the active AI generation task.
  Future<void> stopAiStream(AiStreamReply reply) async {
    _aiStreamChangeBus.removeBySourceMessageId(reply.sourceMessageId);
    if (reply.text.isNotEmpty) {
      _aiStreamReplies[reply.sourceMessageId] = reply.copyWith(
        status: AiStreamStatus.completed,
      );
    } else {
      _aiStreamReplies.remove(reply.sourceMessageId);
    }
    _syncAiStreamElapsedTimer();
    _syncAiRunRecoveryPolling();
    notifyListeners();

    try {
      await _sessionRepository.cancelAiRun(
        runId: reply.runId,
        sessionUnitId: sessionUnitId,
        sourceMessageId: reply.sourceMessageId,
      );
      debugPrint(
        '[ChatTrace] AI stream stopped and backend cancelled | '
        'run=${reply.runId} msg=${reply.sourceMessageId}',
      );
    } catch (exception) {
      debugPrint('[ChatTrace] cancelAiRun error | $exception');
    }
  }

  /// Cancels all currently thinking or streaming AI replies.
  Future<void> stopAllActiveAiStreams() async {
    final active = _aiStreamReplies.values
        .where(
          (reply) =>
              reply.status == AiStreamStatus.thinking ||
              reply.status == AiStreamStatus.streaming,
        )
        .toList(growable: false);
    for (final reply in active) {
      await stopAiStream(reply);
    }
  }

  Future<void> _refreshFriendDetail() async {
    final watch = Stopwatch()..start();
    try {
      final remote = await _sessionRepository.loadRemoteFriendDetail(
        ownerId: effectiveOwnerId,
        sessionUnitId: sessionUnitId,
      );
      friend = remote;
      _title = remote.title;
      if (isOfficialAccount) unawaited(_loadOfficialMenus());
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

  Future<void> refreshSessionDetail() => _refreshFriendDetail();

  Future<void> loadMore() async {
    if (_isDisposed || isLoading || !hasMore) return;
    isLoading = true;
    error = null;
    notifyListeners();
    final watch = Stopwatch()..start();
    try {
      final page = await _repository.loadHistory(
        ownerId: effectiveOwnerId,
        sessionUnitId: sessionUnitId,
        beforeScore: _messages.isEmpty ? null : _messages.last.score,
        limit: pageSize,
      );
      if (_isDisposed) return;
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
      if (_isDisposed) return;
      if (exception is ApiException && exception.statusCode == 403) {
        hasMore = false;
        debugPrint(
          '[loadMore][FORBIDDEN] session=$sessionUnitId Server denied history access (403). Marked hasMore=false.',
        );
      } else {
        error = exception;
        debugPrint(
          '[loadMore][ERROR] session=$sessionUnitId error=$exception\n$stackTrace',
        );
      }
    } finally {
      isLoading = false;
      if (!_isDisposed) {
        notifyListeners();
      }
    }
  }

  Future<void> loadLatest({bool refreshRecent = false}) async {
    if (_isDisposed || isLoadingLatest) return;
    isLoadingLatest = true;
    // The cursor must come from Drift instead of this controller's temporary
    // page.  A new chat controller is created on re-entry, so only the local
    // database can reliably carry forward the newest persisted server ID.
    try {
      if (refreshRecent) {
        try {
          await _repository.loadChanges(
            ownerId: effectiveOwnerId,
            sessionUnitId: sessionUnitId,
          );
        } catch (exception) {
          // Retain the checkpoint for retry without blocking ordinary new messages.
          debugPrint(
            '[loadMessages][changes-failed] session=$sessionUnitId error=$exception',
          );
        }
      }
      final minMessageId = await _repository.getLatestSyncCursor(
        ownerId: effectiveOwnerId,
        sessionUnitId: sessionUnitId,
      );
      final maxLocalId = await _repository.maxLocalServerId(
        ownerId: effectiveOwnerId,
        sessionUnitId: sessionUnitId,
      );
      if (_isDisposed) return;
      if (minMessageId <= 0 && maxLocalId <= 0) {
        if (refreshRecent) {
          // F4: 空会话首次进入或断线重连恢复：通过 refreshRecent 拉取最近快照，建立首屏并校准初始基线
          final recentMessages = await _repository.loadLatest(
            ownerId: effectiveOwnerId,
            sessionUnitId: sessionUnitId,
            minMessageId: 0,
            refreshRecent: true,
          );
          if (_isDisposed) return;
          if (recentMessages.isNotEmpty) {
            final byId = <String, ChatMessage>{
              for (final item in _messages) item.localId: item,
            };
            for (final item in recentMessages) {
              byId[item.localId] = item;
            }
            final merged = byId.values.toList(growable: false)
              ..sort((a, b) => b.score.compareTo(a.score));
            _messages
              ..clear()
              ..addAll(merged);
            notifyListeners();
          }
        }
        return;
      }
      final hasGap = minMessageId > 0 && maxLocalId > minMessageId;
      final shouldRefreshRecent =
          refreshRecent && (hasGap || !_repository.isChangeSyncAvailable);
      final effectiveMinMessageId = minMessageId;
      final latest = await _repository.loadLatest(
        ownerId: effectiveOwnerId,
        sessionUnitId: sessionUnitId,
        minMessageId: effectiveMinMessageId,
        refreshRecent: shouldRefreshRecent,
      );
      if (_isDisposed) return;
      final byId = <String, ChatMessage>{
        for (final item in _messages) item.localId: item,
      };
      for (final item in latest) {
        byId[item.localId] = _retainRollbackState(item, byId[item.localId]);
      }
      _messages
        ..clear()
        ..addAll(byId.values);
      _deduplicateMessages();
      _messages.sort((a, b) => b.score.compareTo(a.score));
    } catch (exception) {
      if (_isDisposed) return;
      debugPrint(
        '[loadMessages][latest-failed] session=$sessionUnitId error=$exception',
      );
    } finally {
      isLoadingLatest = false;
      if (!_isDisposed) {
        notifyListeners();
      }
    }
  }

  @override
  Future<void> send(String text) async {
    final value = text.trim();
    if (value.isEmpty || isSending) return;
    _reportTyping(false);
    if (isMuted) {
      error = StateError('你已被禁言，暂时不能发言');
      notifyListeners();
      return;
    }
    if (isSessionKilled) {
      error = StateError('您已退出该群聊或已被移出，无法发送消息');
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
    _markLiveMessageForAnimation(clientMessageId);
    _replaceMessage(pending);
    notifyListeners();

    // 后台异步发送：即便用户立即返回或关闭聊天页，发送流程依然在后台完成；同时避免在 disposed 时触发 notifyListeners
    unawaited(() async {
      try {
        final sent = await _repository.sendText(
          ownerId: ownerId,
          sessionUnitId: sessionUnitId,
          text: value,
          quote: quote,
          remindList: remindList,
          clientMessageId: clientMessageId,
        );
        if (_isDisposed) return;
        _replaceMessage(sent);
        isSending = false;
        notifyListeners();
        _playSentEffect(sent);
      } catch (_) {
        if (_isDisposed) return;
        isSending = false;
        notifyListeners();
      }
    }());
  }

  @override
  void updateMentionInput(String text) {
    if (text.trim().isNotEmpty) {
      _reportTyping(true, action: 'typing');
    }
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

  @override
  Future<void> loadMoreMentions() =>
      _loadMentions(generation: _mentionGeneration, reset: false);

  @override
  void updateMentionKeyword(String keyword) {
    if (!mentionVisible || keyword == _mentionKeyword) return;
    _mentionKeyword = keyword;
    mentionMembers.clear();
    mentionHasMore = true;
    final generation = ++_mentionGeneration;
    unawaited(_loadMentions(generation: generation, reset: true));
    notifyListeners();
  }

  @override
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

  @override
  bool isMemberMentioned(ChatMember member, String text) {
    final token = '@${member.name}';
    return _mentionedTokens[member.id] == token ||
        RegExp('@${RegExp.escape(member.name)}(?=\\s|\$)').hasMatch(text);
  }

  @override
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

  @override
  Future<void> chooseAndSendFile() async {
    _reportTyping(true, action: 'uploading_file');
    try {
      final files = await _filePickerService.chooseFile(
        const FilePickerRequest(dialogTitle: '选择要发送的文件'),
      );
      if (files.isEmpty) {
        _reportTyping(false);
        return;
      }
      await _sendFile(files.first);
    } catch (exception) {
      error = exception;
      notifyListeners();
    } finally {
      _reportTyping(false);
    }
  }

  @override
  Future<void> chooseAndSendImages() async {
    _reportTyping(true, action: 'uploading_image');
    try {
      final images = await _mediaService.chooseImage(
        const MediaPickRequest(allowMultiple: true, maxCount: 9),
      );
      if (images.isEmpty) {
        _reportTyping(false);
        return;
      }
      for (final image in images) {
        final bytes = await image.readBytes();
        final dims = await _decodeImageDimensions(bytes);
        final local = await _repository.createLocalImage(
          ownerId: ownerId,
          sessionUnitId: sessionUnitId,
          file: image,
          width: dims?.width,
          height: dims?.height,
        );
        _pendingFiles[local.localId] = image;
        _imagePreviews[local.localId] = bytes;
        _markLiveMessageForAnimation(local.localId);
        _replaceMessage(local);
        if (!_isDisposed) notifyListeners();
        uploadProgress[local.localId] = 0;

        final extraFields = <String, Object?>{
          if (dims != null) 'width': dims.width,
          if (dims != null) 'height': dims.height,
        };

        unawaited(() async {
          try {
            final sent = await _repository.sendLocalImage(
              local: local,
              file: image,
              extraFields: extraFields.isNotEmpty ? extraFields : null,
              onProgress: (sent, total) {
                if (_isDisposed) return;
                uploadProgress[local.localId] = total <= 0 ? 0 : sent / total;
                notifyListeners();
              },
            );
            if (_isDisposed) return;
            _replaceMessage(sent);
            if (sent.state == 'sent') _pendingFiles.remove(local.localId);
            uploadProgress.remove(local.localId);
            notifyListeners();
            _playSentEffect(sent);
          } catch (_) {
            if (_isDisposed) return;
            uploadProgress.remove(local.localId);
            notifyListeners();
          }
        }());
      }
    } catch (exception) {
      if (!_isDisposed) {
        error = exception;
        notifyListeners();
      }
    } finally {
      _reportTyping(false);
    }
  }

  @override
  Future<void> takeAndSendPhoto() async {
    final image = await _mediaService.takePhoto(const MediaPickRequest());
    if (image != null) await _sendImage(image);
  }

  @override
  Future<void> chooseAndSendVideo() async {
    _reportTyping(true, action: 'uploading_video');
    try {
      final video = await _mediaService.chooseVideo(
        const MediaPickRequest(maxDuration: Duration(minutes: 10)),
      );
      if (video != null) await _sendVideo(video);
    } finally {
      _reportTyping(false);
    }
  }

  @override
  Future<void> recordAndSendVideo() async {
    final video = await _mediaService.recordVideo(
      const MediaPickRequest(maxDuration: Duration(minutes: 10)),
    );
    if (video != null) await _sendVideo(video);
  }

  /// 发送直接传入的图片 (来自剪贴板或截图)
  Future<void> sendDirectImage(SelectedFile image, {String? caption}) async {
    await _sendImage(image);
    if (caption != null && caption.trim().isNotEmpty) {
      send(caption.trim());
    }
  }

  /// 批量发送直接传入的文件 (来自剪贴板批量粘贴)
  @override
  Future<void> sendDirectFiles(
    List<SelectedFile> files, {
    String? caption,
  }) async {
    for (final file in files) {
      await _sendFile(file);
    }
    if (caption != null && caption.trim().isNotEmpty) {
      send(caption.trim());
    }
  }

  /// 发送图片字节流 (如剪贴板图像或截图产生的 Uint8List)
  @override
  Future<void> sendImageBytes(
    Uint8List bytes, {
    String? caption,
    String? fileName,
  }) async {
    final effectiveName =
        fileName ?? 'image_${DateTime.now().millisecondsSinceEpoch}.png';
    final selected = await SelectedFile.fromBytes(
      bytes,
      name: effectiveName,
      mimeType: 'image/png',
    );
    await sendDirectImage(selected, caption: caption);
  }

  Future<({int width, int height})?> _decodeImageDimensions(
    Uint8List bytes,
  ) async {
    if (bytes.isEmpty) return null;
    ui.Codec? codec;
    ui.FrameInfo? frame;
    try {
      codec = await ui.instantiateImageCodec(bytes);
      frame = await codec.getNextFrame();
      final w = frame.image.width;
      final h = frame.image.height;
      if (w > 0 && h > 0) return (width: w, height: h);
    } catch (_) {
    } finally {
      frame?.image.dispose();
      codec?.dispose();
    }
    return null;
  }

  Future<void> _sendImage(SelectedFile image) async {
    if (isSessionKilled) return;
    final bytes = await image.readBytes();
    final dims = await _decodeImageDimensions(bytes);
    final local = await _repository.createLocalImage(
      ownerId: ownerId,
      sessionUnitId: sessionUnitId,
      file: image,
      width: dims?.width,
      height: dims?.height,
    );
    _pendingFiles[local.localId] = image;
    _imagePreviews[local.localId] = bytes;
    _markLiveMessageForAnimation(local.localId);
    _replaceMessage(local);
    if (!_isDisposed) notifyListeners();
    uploadProgress[local.localId] = 0;

    final extraFields = <String, Object?>{
      if (dims != null) 'width': dims.width,
      if (dims != null) 'height': dims.height,
    };

    unawaited(() async {
      try {
        final sent = await _repository.sendLocalImage(
          local: local,
          file: image,
          extraFields: extraFields.isNotEmpty ? extraFields : null,
          onProgress: (sent, total) {
            if (_isDisposed) return;
            uploadProgress[local.localId] = total <= 0 ? 0 : sent / total;
            notifyListeners();
          },
        );
        if (_isDisposed) return;
        _replaceMessage(sent);
        uploadProgress.remove(local.localId);
        if (sent.state == 'sent') _pendingFiles.remove(local.localId);
        notifyListeners();
        _playSentEffect(sent);
      } catch (_) {
        if (_isDisposed) return;
        uploadProgress.remove(local.localId);
        notifyListeners();
      }
    }());
  }

  Future<void> _sendVideo(SelectedFile video) async {
    if (isSessionKilled) return;
    Uint8List? thumbBytes;
    String? localThumbPath;
    try {
      final bytes = await _mediaService.createVideoThumbnail(video);
      if (bytes.isNotEmpty) {
        thumbBytes = bytes;
        if (!kIsWeb) {
          try {
            final thumbFile = File(
              '${Directory.systemTemp.path}${Platform.pathSeparator}gotoim_video_thumb_${DateTime.now().microsecondsSinceEpoch}.jpg',
            );
            await thumbFile.writeAsBytes(bytes, flush: true);
            localThumbPath = thumbFile.path;
          } catch (_) {
            // Optional local preview file creation; memory bytes still upload as snapshotFile.
          }
        }
      }
    } catch (_) {
      // Unsupported platform or thumbnail extraction failure falls back to backend generation.
    }

    int? width;
    int? height;
    int? durationMs;
    try {
      final meta = await _mediaService.getVideoMetadata(video);
      width = meta.width != null && meta.width! > 0 ? meta.width : null;
      height = meta.height != null && meta.height! > 0 ? meta.height : null;
      durationMs = meta.durationMs != null && meta.durationMs! > 0
          ? meta.durationMs
          : null;
    } catch (_) {
      // Metadata extraction is optional on unsupported platforms.
    }
    if (thumbBytes != null && thumbBytes.isNotEmpty) {
      final thumbDims = await _decodeImageDimensions(thumbBytes);
      if (thumbDims != null && thumbDims.width > 0 && thumbDims.height > 0) {
        if (width == null || height == null) {
          width = thumbDims.width;
          height = thumbDims.height;
        } else {
          final isThumbLandscape = thumbDims.width > thumbDims.height;
          final isMetaLandscape = width > height;
          if (isThumbLandscape != isMetaLandscape) {
            final temp = width;
            width = height;
            height = temp;
          }
        }
      }
    }

    final local = await _repository.createLocalVideo(
      ownerId: ownerId,
      sessionUnitId: sessionUnitId,
      file: video,
      width: width,
      height: height,
      durationMs: durationMs,
      localThumbnailPath: localThumbPath,
    );
    _pendingFiles[local.localId] = video;
    _markLiveMessageForAnimation(local.localId);
    _replaceMessage(local);
    uploadProgress[local.localId] = 0;
    if (!_isDisposed) notifyListeners();

    unawaited(() async {
      try {
        final extraFiles = thumbBytes != null && thumbBytes.isNotEmpty
            ? <String, MultipartUploadFile>{
                'snapshotFile': MultipartUploadFile(
                  name: '${video.name}.jpg',
                  length: thumbBytes.length,
                  openRead: () => Stream<List<int>>.value(thumbBytes!),
                  contentType: 'image/jpeg',
                ),
                'snapshotThumbnailFile': MultipartUploadFile(
                  name: 'thumb_${video.name}.jpg',
                  length: thumbBytes.length,
                  openRead: () => Stream<List<int>>.value(thumbBytes!),
                  contentType: 'image/jpeg',
                ),
              }
            : null;
        final extraFields = <String, Object?>{
          if (width != null) 'width': width,
          if (height != null) 'height': height,
          if (width != null) 'imageWidth': width,
          if (height != null) 'imageHeight': height,
          if (durationMs != null) 'durationMs': durationMs,
        };

        final sent = await _repository.sendLocalVideo(
          local: local,
          file: video,
          extraFields: extraFields.isNotEmpty ? extraFields : null,
          extraFiles: extraFiles,
          onProgress: (sent, total) {
            if (_isDisposed) return;
            uploadProgress[local.localId] = total <= 0 ? 0 : sent / total;
            notifyListeners();
          },
        );
        if (_isDisposed) return;
        _replaceMessage(sent);
        uploadProgress.remove(local.localId);
        if (sent.state == 'sent') _pendingFiles.remove(local.localId);
        notifyListeners();
        _playSentEffect(sent);
      } catch (_) {
        if (_isDisposed) return;
        uploadProgress.remove(local.localId);
        notifyListeners();
      }
    }());
  }

  @override
  void quoteMessage(ChatMessage message) {
    if (message.serverId == null) return;
    quoting = message;
    selectionMode = false;
    selectedLocalIds.clear();
    notifyListeners();
  }

  @override
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
    if (message.messageType == 13) {
      throw StateError('模板消息暂不支持转发');
    }
    await _repository.forward(
      message: message,
      targetSessionUnitIds: <String>[targetSessionUnitId],
    );
  }

  Future<void> forwardSelectedAsHistory(String targetSessionUnitId) async {
    final selected = _messages
        .where((message) => selectedLocalIds.contains(message.localId))
        .toList(growable: false);
    if (selected.any((message) => message.messageType == 13)) {
      throw StateError('所选消息含模板消息，暂不支持合并转发');
    }
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
    if (_isDisposed) return;
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
      final updatedFriend = await _repository.setRead(
        ownerId: ownerId,
        sessionUnitId: sessionUnitId,
        messageId: messageId,
      );
      if (_isDisposed) return;
      friend = updatedFriend;
      notifyListeners();
    } catch (exception) {
      if (_isDisposed) return;
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

  Future<void> _reloadFromLocalChange({
    int? messageId,
    List<int>? messageIds,
  }) async {
    if (_isDisposed) return;
    final affected = {...?messageIds, if (messageId != null) messageId};
    final targets = {
      ...affected,
      for (final item in _messages)
        if (affected.contains(item.quoteMessageId) ||
            affected.contains(asInt(item.quoteMessage['id'])))
          if (item.serverId != null) item.serverId!,
    };
    final latest =
        affected.isNotEmpty
            ? await _repository.loadLocalByIds(
              effectiveOwnerId,
              sessionUnitId,
              targets.toList(),
            )
            : await _repository.loadLocalLatest(
              ownerId: effectiveOwnerId,
              sessionUnitId: sessionUnitId,
            );
    if (_isDisposed) return;
    var receivedIncoming = false;
    for (final message in latest) {
      final known = _messages.any(
        (item) =>
            item.localId == message.localId ||
            (item.serverId != null && item.serverId == message.serverId),
      );
      if (!known && !message.isMine && !message.isRollbacked) {
        receivedIncoming = true;
        _markLiveMessageForAnimation(message.localId);
      }
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

  @override
  Future<void> startVoiceRecording() {
    _reportTyping(true, action: 'recording_voice');
    return _mediaService.startAudioRecording(
      const AudioRecordingRequest(fileNamePrefix: 'gotoim_voice'),
    );
  }

  @override
  Future<bool> hasVoiceRecordingPermission() =>
      _mediaService.hasAudioRecordingPermission();

  Future<double> voiceRecordingLevel() => _mediaService.audioRecordingLevel();

  @override
  Stream<double> voiceRecordingLevels(Duration interval) =>
      _mediaService.audioRecordingLevels(interval);

  @override
  Future<void> cancelVoiceRecording() {
    _reportTyping(false);
    return _mediaService.cancelAudioRecording();
  }

  @override
  Future<void> finishVoiceRecording(Duration duration) async {
    _reportTyping(false);
    final file = await _mediaService.stopAudioRecording();
    if (file == null) return;
    final local = await _repository.createLocalVoice(
      ownerId: ownerId,
      sessionUnitId: sessionUnitId,
      file: file,
      duration: duration,
    );
    _pendingFiles[local.localId] = file;
    _markLiveMessageForAnimation(local.localId);
    _replaceMessage(local);
    if (!_isDisposed) notifyListeners();

    unawaited(() async {
      try {
        final sent = await _repository.sendLocalVoice(
          local: local,
          file: file,
          duration: duration,
        );
        if (_isDisposed) return;
        _replaceMessage(sent);
        if (sent.state == 'sent') _pendingFiles.remove(local.localId);
        notifyListeners();
        _playSentEffect(sent);
      } catch (_) {
        if (!_isDisposed) notifyListeners();
      }
    }());
  }

  Future<void> _sendFile(SelectedFile file) async {
    if (isSessionKilled) return;
    final local = await _repository.createLocalFile(
      ownerId: ownerId,
      sessionUnitId: sessionUnitId,
      file: file,
    );
    _pendingFiles[local.localId] = file;
    _markLiveMessageForAnimation(local.localId);
    _replaceMessage(local);
    if (!_isDisposed) notifyListeners();

    unawaited(() async {
      try {
        final sent = await _repository.sendLocalFile(local: local, file: file);
        if (_isDisposed) return;
        _replaceMessage(sent);
        if (sent.state == 'sent') _pendingFiles.remove(local.localId);
        notifyListeners();
        _playSentEffect(sent);
      } catch (_) {
        if (!_isDisposed) notifyListeners();
      }
    }());
  }

  Future<void> retryFile(ChatMessage message) async {
    var file = _pendingFiles[message.localId];
    if (file == null && message.localFilePath != null && !kIsWeb) {
      final ioFile = File(message.localFilePath!);
      if (ioFile.existsSync()) {
        file = await SelectedFile.fromXFile(XFile(ioFile.path));
        _pendingFiles[message.localId] = file;
      }
    }
    if (file == null || message.state == 'sending') return;
    final sending = message.copyWith(state: 'sending');
    _replaceMessage(sending);
    if (!_isDisposed) notifyListeners();

    unawaited(() async {
      try {
        final sent =
            message.messageType == 3
                ? await _repository.sendLocalVoice(local: sending, file: file!)
                : message.messageType == 2
                ? await _repository.sendLocalImage(
                  local: sending,
                  file: file!,
                  onProgress: (sentBytes, totalBytes) {
                    if (_isDisposed) return;
                    uploadProgress[message.localId] =
                        totalBytes <= 0 ? 0 : sentBytes / totalBytes;
                    notifyListeners();
                  },
                )
                : message.messageType == 4
                ? await _retryLocalVideo(sending, file!)
                : await _repository.sendLocalFile(local: sending, file: file!);
        if (_isDisposed) return;
        _replaceMessage(sent);
        if (sent.state == 'sent') _pendingFiles.remove(message.localId);
        notifyListeners();
        _playSentEffect(sent);
      } catch (error) {
        if (!_isDisposed) {
          final failedMsg = sending.copyWith(
            state: 'failed',
            raw: <String, dynamic>{
              ...sending.raw,
              'errorMessage': '$error',
              'error': '$error',
            },
          );
          _replaceMessage(failedMsg);
          notifyListeners();
        }
      }
    }());
  }

  Future<ChatMessage> _retryLocalVideo(
    ChatMessage sending,
    SelectedFile video,
  ) async {
    Map<String, MultipartUploadFile>? extraFiles;
    try {
      Uint8List? thumbBytes;
      final localThumb = sending.localThumbnailPath;
      if (!kIsWeb && localThumb != null && localThumb.isNotEmpty) {
        final thumbFile = File(localThumb);
        if (thumbFile.existsSync()) {
          thumbBytes = await thumbFile.readAsBytes();
        }
      }
      thumbBytes ??= await _mediaService.createVideoThumbnail(video);
      if (thumbBytes.isNotEmpty) {
        final bytes = thumbBytes;
        extraFiles = <String, MultipartUploadFile>{
          'snapshotFile': MultipartUploadFile(
            name: '${video.name}.jpg',
            length: bytes.length,
            openRead: () => Stream<List<int>>.value(bytes),
            contentType: 'image/jpeg',
          ),
          'snapshotThumbnailFile': MultipartUploadFile(
            name: 'thumb_${video.name}.jpg',
            length: bytes.length,
            openRead: () => Stream<List<int>>.value(bytes),
            contentType: 'image/jpeg',
          ),
        };
      }
    } catch (_) {
      // Fallback to backend snapshot generation.
    }

    final width = asInt(sending.content['width']);
    final height = asInt(sending.content['height']);
    final durationMs = asInt(sending.content['durationMs']);
    final extraFields = <String, Object?>{
      if (width != null && width > 0) 'width': width,
      if (height != null && height > 0) 'height': height,
      if (durationMs != null && durationMs > 0) 'durationMs': durationMs,
    };

    return _repository.sendLocalVideo(
      local: sending,
      file: video,
      extraFields: extraFields.isNotEmpty ? extraFields : null,
      extraFiles: extraFiles,
      onProgress: (sentBytes, totalBytes) {
        if (_isDisposed) return;
        uploadProgress[sending.localId] =
            totalBytes <= 0 ? 0 : sentBytes / totalBytes;
        notifyListeners();
      },
    );
  }

  Future<Map<String, dynamic>> loadUsableTemplates({int skipCount = 0}) =>
      _repository.usableTemplates(ownerId, skipCount: skipCount);

  Future<Map<String, dynamic>> loadTemplateRevision(String id, int version) =>
      _repository.templateRevision(id, version);

  Future<void> sendTemplate(Map<String, dynamic> content,
      Map<String, dynamic> snapshot) async {
    if (isMuted) throw StateError('当前会话不可发送消息');
    final quote = quoting;
    final result = await _repository.sendTemplate(ownerId: ownerId,
        sessionUnitId: sessionUnitId, content: content, snapshot: snapshot, quote: quote);
    if (_isDisposed) return;
    if (result.state == 'sent') cancelQuote();
    _replaceMessage(result);
    notifyListeners();
    _playSentEffect(result);
  }
  Future<void> retryMessage(ChatMessage message) async {
    if (message.state != 'failed') return;
    if (message.messageType == 13) {
      _replaceMessage(message.copyWith(state: 'sending'));
      if (!_isDisposed) notifyListeners();
      final retried = await _repository.retryTemplate(message);
      if (_isDisposed) return;
      _replaceMessage(retried);
      notifyListeners();
      _playSentEffect(retried);
      return;
    }
    if (message.messageType != 0) {
      await retryFile(message);
      return;
    }
    final sending = message.copyWith(state: 'sending');
    _replaceMessage(sending);
    if (!_isDisposed) notifyListeners();

    unawaited(() async {
      try {
        final retried = await _repository.retryText(message);
        if (_isDisposed) return;
        _replaceMessage(retried);
        notifyListeners();
        _playSentEffect(retried);
      } catch (error) {
        if (!_isDisposed) {
          final failedMsg = message.copyWith(
            state: 'failed',
            raw: <String, dynamic>{
              ...message.raw,
              'errorMessage': '$error',
              'error': '$error',
            },
          );
          _replaceMessage(failedMsg);
          notifyListeners();
        }
      }
    }());
  }

  bool canRetryMessage(ChatMessage message) {
    if (message.state != 'failed') return false;
    if (message.messageType == 13) return message.raw['_templateRequest'] is Map;
    if (message.messageType == 0) return true;
    if (_pendingFiles.containsKey(message.localId)) return true;
    if (!kIsWeb && message.localFilePath != null) {
      try {
        return File(message.localFilePath!).existsSync();
      } catch (_) {
        return false;
      }
    }
    return false;
  }

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
      _attachmentTransferService.cancel(
        message.localId,
        userId: ownerId.toString(),
      );

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
    if (_deletedMessageIds.contains(value.serverId)) return;
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
      _messages[index] = _retainRollbackState(value, _messages[index]);
    }
    _deduplicateMessages();
    _messages.sort((a, b) => b.score.compareTo(a.score));
  }

  // Local reads can finish out of order while a sync page commits. Once this
  // view has observed a withdrawal, an earlier read must not restore content.
  ChatMessage _retainRollbackState(ChatMessage incoming, ChatMessage? known) {
    if (known == null) return incoming;
    final raw = <String, dynamic>{...incoming.raw};
    if (known.isRollbacked) {
      raw['isRollbacked'] = true;
      raw['rollbackTime'] = known.raw['rollbackTime'];
    }
    final quoteId = asInt(incoming.quoteMessage['id']);
    if (quoteId != null &&
        quoteId == asInt(known.quoteMessage['id']) &&
        known.quoteMessage['isDeleted'] == true) {
      raw['quoteMessage'] = {
        ...incoming.quoteMessage,
        'isDeleted': true,
        'content': null,
      };
    }
    if (quoteId != null &&
        quoteId == asInt(known.quoteMessage['id']) &&
        (known.quoteMessage['isRollbacked'] == true ||
            known.quoteMessage['rollbackTime'] != null)) {
      raw['quoteMessage'] = {
        ...incoming.quoteMessage,
        'isRollbacked': true,
        'rollbackTime': known.quoteMessage['rollbackTime'],
      };
    }
    return incoming.copyWith(raw: raw);
  }

  void _deduplicateMessages() {
    final seenLocalIds = <String>{};
    final seenServerIds = <int>{};
    final seenClientIds = <String>{};
    _messages.removeWhere((item) {
      if (_deletedMessageIds.contains(item.serverId)) return true;
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
    _isDisposed = true;
    _reportTyping(false);
    _typingService.removeListener(notifyListeners);
    _typingService.dispose();
    _attachmentTransferService.removeListener(_onAttachmentTransferChanged);
    unawaited(_sessionChangeSubscription?.cancel());
    unawaited(_aiStreamSubscription?.cancel());
    unawaited(_signalRSubscription?.cancel());
    _aiStreamElapsedTimer?.cancel();
    _aiStreamElapsedTimer = null;
    _aiRunRecoveryTimer?.cancel();
    _aiRunRecoveryTimer = null;
    super.dispose();
  }

  void _onAiStreamEvent(AiStreamEvent event) {
    if (_isDisposed || event.requesterSessionUnitId != sessionUnitId) return;
    _restoreAiStreamReplies();
    _syncAiStreamElapsedTimer();
    _syncAiRunRecoveryPolling();
    notifyListeners();
  }

  void _onSignalREvent(SignalRAppEvent event) {
    if (_isDisposed) return;
    if (event is SignalRTypingEvent) {
      final sId = friend?.sessionId ?? sessionUnitId;
      if (event.sessionId == sId || event.sessionId == sessionUnitId) {
        _typingService.handleTypingEvent(event, mySessionUnitId: sessionUnitId);
      }
      return;
    }
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
    if (_isDisposed || _isRecoveringAfterRealtimeReconnect) return;
    _isRecoveringAfterRealtimeReconnect = true;
    final watch = Stopwatch()..start();
    try {
      await _restoreActiveAiRun();
      await _refreshFriendDetail();
      await loadLatest(refreshRecent: true);
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
