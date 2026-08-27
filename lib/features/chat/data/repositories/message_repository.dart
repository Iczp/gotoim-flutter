import 'package:flutter/foundation.dart';

import '../datasources/message_api.dart';
import '../datasources/message_dao.dart';
import '../models/chat_message.dart';

class MessageRepository {
  MessageRepository({required MessageApi api, required MessageDao dao})
    : _api = api,
      _dao = dao;
  final MessageApi _api;
  final MessageDao _dao;

  Future<MessagePage> loadHistory({
    required int ownerId,
    required String sessionUnitId,
    int? beforeScore,
    int limit = 30,
  }) async {
    final local = await _dao.readPage(
      ownerId: ownerId,
      sessionUnitId: sessionUnitId,
      beforeScore: beforeScore,
      limit: limit,
    );
    debugPrint(
      '[loadMessages][local] session=$sessionUnitId added=${local.length}',
    );
    if (local.length >= limit) return MessagePage(local, true);
    final cursorScore = local.isNotEmpty ? local.last.score : beforeScore;
    final maxMessageId = cursorScore == null ? null : cursorScore ~/ 1000000;
    try {
      final remote = await _api.history(
        ownerId: ownerId,
        sessionUnitId: sessionUnitId,
        limit: limit - local.length,
        maxMessageId: maxMessageId == 0 ? null : maxMessageId,
      );
      await _dao.upsertAll(remote.items);
      debugPrint(
        '[loadMessages][remote] session=$sessionUnitId maxMessageId=$maxMessageId '
        'received=${remote.items.length} persisted=${remote.items.length}',
      );
      final all =
          <String, ChatMessage>{
              for (final item in local) item.localId: item,
              for (final item in remote.items) item.localId: item,
            }.values.toList()
            ..sort((a, b) => b.score.compareTo(a.score));
      return MessagePage(all, remote.items.length == limit - local.length);
    } catch (error) {
      if (local.isNotEmpty) return MessagePage(local, true);
      rethrow;
    }
  }

  Future<ChatMessage> sendText({
    required int ownerId,
    required String sessionUnitId,
    required String text,
  }) async {
    final clientId = '${DateTime.now().microsecondsSinceEpoch}';
    final maxScore = await _dao.maxScore(ownerId, sessionUnitId);
    var local = ChatMessage(
      localId: clientId,
      serverId: null,
      clientMessageId: clientId,
      ownerId: ownerId,
      sessionUnitId: sessionUnitId,
      senderSessionUnitId: sessionUnitId,
      messageType: 0,
      state: 'sending',
      score: maxScore + 1,
      createdAt: DateTime.now(),
      raw: <String, dynamic>{
        'messageType': 0,
        'content': <String, dynamic>{'text': text},
      },
    );
    await _dao.upsertAll(<ChatMessage>[local]);
    try {
      final response = await _api.sendText(
        sessionUnitId: sessionUnitId,
        clientMessageId: clientId,
        text: text,
      );
      final serverId =
          response['id'] is num
              ? (response['id'] as num).toInt()
              : int.tryParse('${response['id']}');
      local = local.copyWith(
        serverId: serverId,
        score: serverId == null ? local.score : serverId * 1000000,
        state: 'sent',
        raw: response,
      );
    } catch (_) {
      local = local.copyWith(state: 'failed');
    }
    await _dao.upsertAll(<ChatMessage>[local]);
    return local;
  }
}

class MessagePage {
  const MessagePage(this.items, this.hasMore);
  final List<ChatMessage> items;
  final bool hasMore;
}
