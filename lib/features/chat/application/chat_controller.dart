import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../app/application_providers.dart';
import '../../../core/config/app_environment.dart';
import '../../../core/native/native.dart';
import '../../../core/realtime/signalr_gateway.dart';
import '../../../core/services/clipboard_service.dart';
import '../../../core/services/file/file_picker_service.dart';
import '../../../core/services/media/media_service.dart';
import '../../../core/services/media/audio_playback_service.dart';
import '../../../core/services/media/voice_cache_service.dart';
import 'chat_unread_divider.dart';
import '../data/datasources/message_api.dart';
import '../data/datasources/message_dao.dart';
import '../data/models/chat_message.dart';
import '../data/repositories/message_repository.dart';
import '../../session/data/models/session_summary.dart';
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

class ChatController extends ChangeNotifier {
  ChatController(
    this._repository,
    this._sessionRepository, {
    required FilePickerService filePickerService,
    required MediaService mediaService,
    required AudioPlaybackService audioPlaybackService,
    required SignalRGateway signalRGateway,
    required ClipboardService clipboardService,
    required ChatSettingsRepository chatSettingsRepository,
    required this.ownerId,
    required this.sessionUnitId,
    required String initialTitle,
  }) : _filePickerService = filePickerService,
       _mediaService = mediaService,
       _audioPlaybackService = audioPlaybackService,
       _signalRGateway = signalRGateway,
       _clipboardService = clipboardService,
       _chatSettingsRepository = chatSettingsRepository,
       _title = initialTitle;
  static const pageSize = 30;
  static const initialPageSize = 10;
  final MessageRepository _repository;
  final SessionRepository _sessionRepository;
  final FilePickerService _filePickerService;
  final MediaService _mediaService;
  final AudioPlaybackService _audioPlaybackService;
  final SignalRGateway _signalRGateway;
  final ClipboardService _clipboardService;
  final ChatSettingsRepository _chatSettingsRepository;
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
  StreamSubscription<SignalRAppEvent>? _realtimeSubscription;
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

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  String get title => friend?.title ?? _title;
  bool get isMuted => friend?.isMuted == true;
  Uint8List? imagePreview(String localId) => _imagePreviews[localId];
  String get mentionKeyword => _mentionKeyword;
  int? get initialUnreadDividerMessageId => _initialUnreadDividerMessageId;

  Future<void> initialize() async {
    _realtimeSubscription = _signalRGateway.events.listen(_handleRealtimeEvent);
    final local = await _sessionRepository.loadLocalFriendDetail(sessionUnitId);
    if (local != null) {
      friend = local;
      _title = local.title;
      debugPrint(
        '[chatInitialize][local-friend] session=$sessionUnitId title=$_title',
      );
      notifyListeners();
    }
    unawaited(_refreshFriendDetail());
    await _loadInitialLocal();
    if (_messages.isEmpty && hasMore) {
      await loadMore();
    }
    // Snapshot the local read position before the asynchronous read receipt is
    // submitted. Later realtime messages must never create a historical
    // unread divider while the user is already viewing the latest message.
    _initialUnreadDividerMessageId = findInitialUnreadDividerMessageId(
      messages: _messages,
      readMessageId: friend?.readMessageId,
    );
    if (_messages.isNotEmpty) {
      unawaited(loadLatest().then((_) => markLatestRead()));
    }
  }

  Future<void> _loadInitialLocal() async {
    isLoading = true;
    notifyListeners();
    try {
      final page = await _repository.loadInitialLocal(
        ownerId: ownerId,
        sessionUnitId: sessionUnitId,
        limit: initialPageSize,
      );
      _messages
        ..clear()
        ..addAll(page.items);
      hasMore = page.hasMore;
    } catch (exception) {
      error = exception;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _refreshFriendDetail() async {
    try {
      final remote = await _sessionRepository.loadRemoteFriendDetail(
        ownerId: ownerId,
        sessionUnitId: sessionUnitId,
      );
      friend = remote;
      _title = remote.title;
      notifyListeners();
    } catch (exception) {
      debugPrint(
        '[chatInitialize][remote-friend-failed] session=$sessionUnitId '
        'keepLocal=${friend != null} error=$exception',
      );
    }
  }

  Future<void> loadMore() async {
    if (isLoading || !hasMore) return;
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final page = await _repository.loadHistory(
        ownerId: ownerId,
        sessionUnitId: sessionUnitId,
        beforeScore: _messages.isEmpty ? null : _messages.last.score,
        limit: pageSize,
      );
      final ids = _messages.map((item) => item.localId).toSet();
      _messages.addAll(page.items.where((item) => ids.add(item.localId)));
      _messages.sort((a, b) => b.score.compareTo(a.score));
      hasMore = page.hasMore;
    } catch (exception) {
      error = exception;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadLatest() async {
    if (isLoadingLatest || _messages.isEmpty) return;
    final minMessageId = _messages
        .map((item) => item.serverId ?? 0)
        .fold<int>(0, (max, id) => id > max ? id : max);
    if (minMessageId <= 0) return;
    isLoadingLatest = true;
    try {
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
        ..addAll(byId.values)
        ..sort((a, b) => b.score.compareTo(a.score));
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
    final pending = ChatMessage(
      localId: '${DateTime.now().microsecondsSinceEpoch}',
      serverId: null,
      clientMessageId: null,
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
    _messages.insert(0, pending);
    notifyListeners();
    final sent = await _repository.sendText(
      ownerId: ownerId,
      sessionUnitId: sessionUnitId,
      text: value,
      quote: quote,
      remindList: remindList,
    );
    _messages.remove(pending);
    _messages.insert(0, sent);
    _messages.sort((a, b) => b.score.compareTo(a.score));
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
        _messages.insert(0, local);
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
    _messages.insert(0, local);
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
    _messages.insert(0, local);
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
    if (messageId <= 0 || messageId == _lastSubmittedReadMessageId) return;
    try {
      friend = await _repository.setRead(
        ownerId: ownerId,
        sessionUnitId: sessionUnitId,
        messageId: messageId,
      );
      _lastSubmittedReadMessageId = messageId;
      newMessageCount = 0;
      notifyListeners();
    } catch (exception) {
      debugPrint(
        '[setRead][failed] session=$sessionUnitId messageId=$messageId error=$exception',
      );
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

  void _handleRealtimeEvent(SignalRAppEvent event) {
    if (event is! SignalRCommandEvent) return;
    switch (event.command) {
      case SignalRCommand.messageCreated:
      case SignalRCommand.messageForwarded:
      case SignalRCommand.messageUpdated:
      case SignalRCommand.messageRollbacked:
        unawaited(_applyRealtimeThenSync(event));
      default:
        break;
    }
  }

  Future<void> _applyRealtimeThenSync(SignalRCommandEvent event) async {
    final message = await _repository.applyRealtimePayload(
      ownerId: ownerId,
      sessionUnitId: sessionUnitId,
      payload: event.payload,
    );
    if (message != null) {
      final isNewIncoming =
          !message.isMine &&
          !_messages.any((item) => item.serverId == message.serverId);
      if (isNewIncoming && !_viewingLatest) newMessageCount++;
      final serverIndex = _messages.indexWhere(
        (item) => item.serverId != null && item.serverId == message.serverId,
      );
      if (serverIndex >= 0) {
        _messages[serverIndex] = message;
      } else {
        _replaceMessage(message);
      }
      notifyListeners();
      if (isNewIncoming && _viewingLatest) unawaited(markLatestRead());
    }
    await loadLatest();
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
    _messages.insert(0, local);
    _messages.sort((a, b) => b.score.compareTo(a.score));
    notifyListeners();
    final sent = await _repository.sendLocalVoice(local: local, file: file);
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
    _messages.insert(0, local);
    _messages.sort((a, b) => b.score.compareTo(a.score));
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
    _replaceMessage(updated);
    notifyListeners();
    await _repository.markOpened(message.localId);
  }

  void _replaceMessage(ChatMessage value) {
    final index = _messages.indexWhere(
      (message) => message.localId == value.localId,
    );
    if (index < 0) {
      _messages.insert(0, value);
    } else {
      _messages[index] = value;
    }
    _messages.sort((a, b) => b.score.compareTo(a.score));
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
    unawaited(_realtimeSubscription?.cancel());
    super.dispose();
  }
}
