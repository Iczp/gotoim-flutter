import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/application_providers.dart';
import '../../../core/services/file/file_picker_service.dart';
import '../data/datasources/message_api.dart';
import '../data/datasources/message_dao.dart';
import '../data/models/chat_message.dart';
import '../data/repositories/message_repository.dart';
import '../../session/data/models/session_summary.dart';
import '../../session/data/datasources/session_dao.dart';
import '../../session/data/repositories/session_repository.dart';
import '../../session/data/session_change_bus.dart';

final messageRepositoryProvider = Provider<MessageRepository>(
  (ref) => MessageRepository(
    api: MessageApi(ref.watch(apiClientProvider)),
    dao: MessageDao(ref.watch(unifiedDatabaseProvider)),
    sessionDao: SessionDao(ref.watch(unifiedDatabaseProvider)),
    sessionChangeBus: ref.watch(sessionChangeBusProvider),
  ),
);

class ChatController extends ChangeNotifier {
  ChatController(
    this._repository,
    this._sessionRepository, {
    required FilePickerService filePickerService,
    required this.ownerId,
    required this.sessionUnitId,
    required String initialTitle,
  }) : _filePickerService = filePickerService,
       _title = initialTitle;
  static const pageSize = 30;
  static const initialPageSize = 10;
  final MessageRepository _repository;
  final SessionRepository _sessionRepository;
  final FilePickerService _filePickerService;
  final int ownerId;
  final String sessionUnitId;
  final List<ChatMessage> _messages = <ChatMessage>[];
  final Map<String, SelectedFile> _pendingFiles = <String, SelectedFile>{};
  bool isLoading = false;
  bool isSending = false;
  bool isLoadingLatest = false;
  bool hasMore = true;
  Object? error;
  SessionSummary? friend;
  String _title;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  String get title => friend?.title ?? _title;

  Future<void> initialize() async {
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
    if (_messages.isNotEmpty) {
      unawaited(loadLatest());
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
    isSending = true;
    notifyListeners();
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
      },
    );
    _messages.insert(0, pending);
    notifyListeners();
    final sent = await _repository.sendText(
      ownerId: ownerId,
      sessionUnitId: sessionUnitId,
      text: value,
    );
    _messages.remove(pending);
    _messages.insert(0, sent);
    _messages.sort((a, b) => b.score.compareTo(a.score));
    isSending = false;
    notifyListeners();
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
  }

  Future<void> retryFile(ChatMessage message) async {
    final file = _pendingFiles[message.localId];
    if (file == null || message.state == 'sending') return;
    final sending = message.copyWith(state: 'sending');
    _replaceMessage(sending);
    notifyListeners();
    final sent = await _repository.sendLocalFile(local: sending, file: file);
    _replaceMessage(sent);
    if (sent.state == 'sent') _pendingFiles.remove(message.localId);
    notifyListeners();
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
    _timeVisibilityResetMarker++;
    hasMore = true;
    error = null;
    isLoading = false;
    isLoadingLatest = false;
    notifyListeners();
  }

  int _timeVisibilityResetMarker = 0;
  int get timeVisibilityResetMarker => _timeVisibilityResetMarker;
}
