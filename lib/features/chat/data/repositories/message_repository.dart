import 'package:flutter/foundation.dart';

import '../../../../core/services/file/file_picker_service.dart';
import '../../../session/data/datasources/session_dao.dart';
import '../../../session/data/session_change_bus.dart';
import '../datasources/message_api.dart';
import '../datasources/message_dao.dart';
import '../models/chat_message.dart';

class MessageRepository {
  MessageRepository({
    required MessageApi api,
    required MessageDao dao,
    SessionDao? sessionDao,
    SessionChangeBus? sessionChangeBus,
  }) : _api = api,
       _dao = dao,
       _sessionDao = sessionDao,
       _sessionChangeBus = sessionChangeBus;
  final MessageApi _api;
  final MessageDao _dao;
  final SessionDao? _sessionDao;
  final SessionChangeBus? _sessionChangeBus;

  Future<MessagePage> loadInitialLocal({
    required int ownerId,
    required String sessionUnitId,
    int limit = 10,
  }) async {
    final local = await _dao.readPage(
      ownerId: ownerId,
      sessionUnitId: sessionUnitId,
      limit: limit,
    );
    final loadedAll = await _dao.isLoadedAll(sessionUnitId);
    debugPrint(
      '[loadMessages][initial-local] session=$sessionUnitId '
      'requested=$limit added=${local.length} loadedAll=$loadedAll',
    );
    return MessagePage(local, !(loadedAll && local.length < limit));
  }

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
      '[loadMessages][local-page] session=$sessionUnitId '
      'requested=$limit added=${local.length}',
    );
    if (local.length >= limit) return MessagePage(local, true);
    final loadedAll = await _dao.isLoadedAll(sessionUnitId);
    debugPrint(
      '[loadMessages][loaded-all-check] session=$sessionUnitId '
      'loadedAll=$loadedAll localAdded=${local.length}',
    );
    if (loadedAll) return MessagePage(local, false);
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
      final requestedRemoteCount = limit - local.length;
      final hasMore = remote.items.length >= requestedRemoteCount;
      if (!hasMore) {
        await _dao.markLoadedAll(sessionUnitId, true);
        debugPrint(
          '[loadMessages][mark-loaded-all] session=$sessionUnitId '
          'received=${remote.items.length} requested=$requestedRemoteCount',
        );
      }
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
      return MessagePage(all, hasMore);
    } catch (error) {
      if (local.isNotEmpty) return MessagePage(local, true);
      rethrow;
    }
  }

  Future<List<ChatMessage>> loadLatest({
    required int ownerId,
    required String sessionUnitId,
    required int minMessageId,
    int limit = 99,
    int maxPages = 10,
  }) async {
    var cursor = minMessageId;
    final collected = <String, ChatMessage>{};
    for (var pageIndex = 0; pageIndex < maxPages; pageIndex++) {
      final page = await _api.latest(
        ownerId: ownerId,
        sessionUnitId: sessionUnitId,
        limit: limit,
        minMessageId: cursor,
      );
      if (page.items.isEmpty) break;
      for (final item in page.items) {
        collected[item.localId] = item;
      }
      final next = page.items
          .map((item) => item.serverId ?? 0)
          .fold<int>(cursor, (max, id) => id > max ? id : max);
      if (page.items.length < limit || next <= cursor) break;
      cursor = next;
    }
    final items = collected.values.toList(growable: false);
    await _dao.upsertAll(items);
    if (items.isNotEmpty) {
      final newest = [...items]
        ..sort((a, b) => (b.serverId ?? 0).compareTo(a.serverId ?? 0));
      await _updateSessionSummary(newest.first);
    }
    debugPrint(
      '[loadMessages][latest] session=$sessionUnitId minMessageId=$minMessageId '
      'received=${items.length} persisted=${items.length}',
    );
    return items;
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
    if (local.state == 'sent') await _updateSessionSummary(local);
    return local;
  }

  Future<ChatMessage> createLocalFile({
    required int ownerId,
    required String sessionUnitId,
    required SelectedFile file,
  }) async {
    final clientId = '${DateTime.now().microsecondsSinceEpoch}';
    final maxScore = await _dao.maxScore(ownerId, sessionUnitId);
    final now = DateTime.now();
    final message = ChatMessage(
      localId: clientId,
      serverId: null,
      clientMessageId: clientId,
      ownerId: ownerId,
      sessionUnitId: sessionUnitId,
      senderSessionUnitId: sessionUnitId,
      messageType: 5,
      state: 'sending',
      score: maxScore + 1,
      createdAt: now,
      raw: <String, dynamic>{
        'messageType': 5,
        'creationTime': now.toIso8601String(),
        'content': <String, dynamic>{
          'fileName': file.name,
          'contentType': file.mimeType ?? 'application/octet-stream',
          'size': file.size,
          'suffix': file.extension == null ? '' : '.${file.extension}',
          if (file.originalPath != null) 'path': file.originalPath,
        },
      },
    );
    await _dao.upsertAll(<ChatMessage>[message]);
    debugPrint(
      '[sendFile][local] session=$sessionUnitId localId=$clientId '
      'name=${file.name} size=${file.size} state=sending',
    );
    return message;
  }

  Future<ChatMessage> sendLocalFile({
    required ChatMessage local,
    required SelectedFile file,
  }) async {
    var result = local;
    try {
      final response = await _api.sendUploadFile(
        sessionUnitId: local.sessionUnitId,
        fileName: file.name,
        fileLength: file.size,
        openRead: file.readAsByteStream,
      );
      final serverId =
          response['id'] is num
              ? (response['id'] as num).toInt()
              : int.tryParse('${response['id']}');
      result = local.copyWith(
        serverId: serverId,
        score: serverId == null ? local.score : serverId * 1000000,
        state: 'sent',
        raw: response,
      );
      debugPrint(
        '[sendFile][remote] session=${local.sessionUnitId} '
        'localId=${local.localId} serverId=$serverId state=sent',
      );
    } catch (error) {
      result = local.copyWith(
        state: 'failed',
        raw: <String, dynamic>{...local.raw, 'error': '$error'},
      );
      debugPrint(
        '[sendFile][failed] session=${local.sessionUnitId} '
        'localId=${local.localId} error=$error',
      );
    }
    await _dao.upsertAll(<ChatMessage>[result]);
    if (result.state == 'sent') await _updateSessionSummary(result);
    return result;
  }

  Future<void> _updateSessionSummary(ChatMessage message) async {
    await _sessionDao?.updateLastMessage(
      ownerId: message.ownerId,
      sessionUnitId: message.sessionUnitId,
      score: message.score,
      message: message.raw,
    );
    _sessionChangeBus?.publish(
      ownerId: message.ownerId,
      sessionUnitId: message.sessionUnitId,
    );
  }
}

class MessagePage {
  const MessagePage(this.items, this.hasMore);
  final List<ChatMessage> items;
  final bool hasMore;
}
