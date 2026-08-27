import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/application_providers.dart';
import '../data/datasources/message_api.dart';
import '../data/datasources/message_dao.dart';
import '../data/models/chat_message.dart';
import '../data/repositories/message_repository.dart';

final messageRepositoryProvider = Provider<MessageRepository>(
  (ref) => MessageRepository(
    api: MessageApi(ref.watch(apiClientProvider)),
    dao: MessageDao(ref.watch(unifiedDatabaseProvider)),
  ),
);

class ChatController extends ChangeNotifier {
  ChatController(
    this._repository, {
    required this.ownerId,
    required this.sessionUnitId,
  });
  static const pageSize = 30;
  final MessageRepository _repository;
  final int ownerId;
  final String sessionUnitId;
  final List<ChatMessage> _messages = <ChatMessage>[];
  bool isLoading = false;
  bool isSending = false;
  bool hasMore = true;
  Object? error;

  List<ChatMessage> get messages => List.unmodifiable(_messages);

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
}
