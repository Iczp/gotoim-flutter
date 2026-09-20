import 'package:flutter/foundation.dart';

import '../../../../core/services/file/file_picker_service.dart';
import '../../../session/data/datasources/session_dao.dart';
import '../../../session/data/session_change_bus.dart';
import '../../../session/data/models/session_summary_helpers.dart';
import '../../../session/data/models/session_summary.dart';
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

  Future<void> markOpened(String localId) => _dao.markOpened(localId);
  Future<void> deleteLocal(Iterable<String> localIds) =>
      _dao.deleteAll(localIds);

  Future<List<ChatMessage>> loadLocalLatest({
    required int ownerId,
    required String sessionUnitId,
    int limit = 99,
  }) => _dao.readPage(
    ownerId: ownerId,
    sessionUnitId: sessionUnitId,
    limit: limit,
  );

  Future<ChatMessage?> findLocalByServerId({
    required int ownerId,
    required String sessionUnitId,
    required int serverId,
  }) => _dao.findByServerId(
    ownerId: ownerId,
    sessionUnitId: sessionUnitId,
    serverId: serverId,
  );

  Future<int> maxLocalServerId({
    required int ownerId,
    required String sessionUnitId,
  }) => _dao.maxServerId(ownerId, sessionUnitId);

  /// Retries a failed text message in-place so its local identity and UI slot
  /// remain stable instead of inserting a duplicate bubble.
  Future<ChatMessage> retryText(ChatMessage message) async {
    if (message.messageType != 0 || message.state == 'sending') return message;
    var result = message.copyWith(state: 'sending');
    await _dao.upsertAll(<ChatMessage>[result]);
    try {
      final response = await _api.sendText(
        sessionUnitId: message.sessionUnitId,
        clientMessageId: message.clientMessageId ?? message.localId,
        text: message.text,
        quoteMessageId: _asInt(message.raw['quoteMessageId']),
      );
      final serverId = _asInt(response['id']);
      result = result.copyWith(
        serverId: serverId,
        score: serverId == null ? result.score : serverId * 1000000,
        state: 'sent',
        raw: <String, dynamic>{...result.raw, ...response},
      );
    } catch (_) {
      result = result.copyWith(state: 'failed');
    }
    await _dao.upsertAll(<ChatMessage>[result]);
    if (result.state == 'sent') await _updateSessionSummary(result);
    return result;
  }

  Future<SessionSummary> setRead({
    required int ownerId,
    required String sessionUnitId,
    required int messageId,
  }) async {
    final raw = await _api.setRead(
      sessionUnitId: sessionUnitId,
      messageId: messageId,
    );
    final remote = SessionSummary.fromJson(<String, dynamic>{
      ...raw,
      'ownerId': raw['ownerId'] ?? ownerId,
    });
    // Set-read is a state acknowledgement, not an authoritative peer profile
    // response. Keep destination (the AI/contact) from the local Friend when
    // that endpoint returns only session fields.
    final cachedOwner = await _currentOwnerSnapshot(ownerId);
    final friend = (remote.mergeWithLocal(
      await _sessionDao?.readById(sessionUnitId),
    )).withCurrentOwnerFallback(cachedOwner);
    await _sessionDao?.upsertAll(<SessionSummary>[friend]);
    _sessionChangeBus?.publish(ownerId: ownerId, sessionUnitId: sessionUnitId);
    return friend;
  }

  Future<Map<String, dynamic>?> _currentOwnerSnapshot(int ownerId) async {
    final owners = await _sessionDao?.readOwners();
    if (owners == null) return null;
    for (final owner in owners) {
      if (owner.id != ownerId) continue;
      return <String, dynamic>{
        'id': owner.id,
        'displayName': owner.name,
        'thumbnail': owner.imageUrl,
        'objectTypeDescription': owner.typeDescription,
      };
    }
    return null;
  }

  Future<void> deleteRemote(ChatMessage message) async {
    if (message.serverId == null) return;
    await _api.deleteMessage(
      sessionUnitId: message.sessionUnitId,
      messageId: message.serverId!,
    );
    await _dao.deleteAll(<String>[message.localId]);
    final newest = await _dao.readPage(
      ownerId: message.ownerId,
      sessionUnitId: message.sessionUnitId,
      limit: 1,
    );
    if (newest.isNotEmpty) {
      await _updateSessionSummary(newest.first);
    } else {
      await _sessionDao?.resetMessages(message.ownerId, message.sessionUnitId);
      _sessionChangeBus?.publish(
        ownerId: message.ownerId,
        sessionUnitId: message.sessionUnitId,
      );
    }
  }

  Future<ChatMessage> rollback(ChatMessage message) async {
    if (message.serverId == null) throw StateError('消息尚未发送成功');
    await _api.rollback(message.serverId!);
    final updated = message.copyWith(
      raw: <String, dynamic>{
        ...message.raw,
        'isRollbacked': true,
        'rollbackTime': DateTime.now().toIso8601String(),
      },
    );
    await _dao.upsertAll(<ChatMessage>[updated]);
    return updated;
  }

  Future<List<ChatMessage>> forward({
    required ChatMessage message,
    required List<String> targetSessionUnitIds,
  }) async {
    if (message.serverId == null) throw StateError('消息尚未发送成功');
    final values = await _api.forward(
      sessionUnitId: message.sessionUnitId,
      messageId: message.serverId!,
      targetSessionUnitIds: targetSessionUnitIds,
    );
    return values
        .map(
          (json) => ChatMessage.fromJson(
            json,
            ownerId: message.ownerId,
            sessionUnitId:
                json['sessionUnitId']?.toString() ?? message.sessionUnitId,
          ),
        )
        .toList(growable: false);
  }

  Future<void> forwardHistory({
    required String targetSessionUnitId,
    required List<int> messageIds,
  }) async {
    if (messageIds.isEmpty) throw StateError('请至少选择一条已发送消息');
    await _api.sendHistory(
      sessionUnitId: targetSessionUnitId,
      clientMessageId: '${DateTime.now().microsecondsSinceEpoch}',
      messageIds: messageIds,
    );
  }

  Future<ChatMessage> sendLink({
    required int ownerId,
    required String sessionUnitId,
    required String url,
    String? title,
    String? description,
    String? image,
    int? quoteMessageId,
    List<String>? remindList,
  }) async {
    final clientMessageId = '${DateTime.now().microsecondsSinceEpoch}';
    final maxScore = await _dao.maxScore(ownerId, sessionUnitId);
    final now = DateTime.now();
    final localMessage = ChatMessage(
      localId: clientMessageId,
      serverId: null,
      clientMessageId: clientMessageId,
      ownerId: ownerId,
      sessionUnitId: sessionUnitId,
      senderSessionUnitId: sessionUnitId,
      messageType: 6,
      state: 'sending',
      score: maxScore + 1,
      createdAt: now,
      raw: <String, dynamic>{
        'messageType': 6,
        'creationTime': now.toIso8601String(),
        'content': <String, dynamic>{
          'url': url,
          if (title != null && title.isNotEmpty) 'title': title,
          if (description != null && description.isNotEmpty)
            'description': description,
          if (image != null && image.isNotEmpty) 'image': image,
        },
        if (quoteMessageId != null) 'quoteMessageId': quoteMessageId,
        if (remindList != null && remindList.isNotEmpty) 'remindList': remindList,
      },
    );
    await _dao.upsertAll(<ChatMessage>[localMessage]);

    var result = localMessage;
    try {
      final response = await _api.sendLink(
        sessionUnitId: sessionUnitId,
        clientMessageId: clientMessageId,
        url: url,
        title: title,
        description: description,
        image: image,
        quoteMessageId: quoteMessageId,
        remindList: remindList,
      );
      final serverId = asInt(response['id']);
      result = result.copyWith(
        serverId: serverId,
        score: serverId == null ? result.score : serverId * 1000000,
        state: 'sent',
        raw: <String, dynamic>{...result.raw, ...response},
      );
    } catch (_) {
      result = result.copyWith(state: 'failed');
    }
    await _dao.upsertAll(<ChatMessage>[result]);
    if (result.state == 'sent') await _updateSessionSummary(result);
    return result;
  }

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
    // 本地无消息时，忽略 loadedAll flag，始终允许向远端拉取。
    // loadedAll=true 可能是残留状态（数据库清空、账号切换后未重置），
    // 不能用来阻断首次远端加载。
    if (local.isEmpty) {
      debugPrint(
        '[loadMessages][initial-local] session=$sessionUnitId '
        'requested=$limit added=0 → hasMore=true (ignoring loadedAll flag)',
      );
      return MessagePage(const <ChatMessage>[], true);
    }
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
      debugPrint(
        '[loadHistory][ERROR] session=$sessionUnitId '
        'maxMessageId=$maxMessageId error=$error',
      );
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
    final persistedMaxMessageId = await _dao.maxServerId(
      ownerId,
      sessionUnitId,
    );
    if (items.isNotEmpty) {
      final newest = [...items]
        ..sort((a, b) => (b.serverId ?? 0).compareTo(a.serverId ?? 0));
      await _updateSessionSummary(newest.first);
    }
    debugPrint(
      '[loadMessages][latest] session=$sessionUnitId minMessageId=$minMessageId '
      'received=${items.length} persistedMaxMessageId=$persistedMaxMessageId',
    );
    return items;
  }

  Future<ChatMessage> sendText({
    required int ownerId,
    required String sessionUnitId,
    required String text,
    ChatMessage? quote,
    List<String> remindList = const <String>[],
    String? clientMessageId,
  }) async {
    final clientId =
        (clientMessageId != null && clientMessageId.isNotEmpty)
            ? clientMessageId
            : '${DateTime.now().microsecondsSinceEpoch}';
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
        if (quote?.serverId != null) 'quoteMessageId': quote!.serverId,
        if (quote != null) 'quoteMessage': quote.raw,
        if (remindList.isNotEmpty) 'remindList': remindList,
      },
    );
    await _dao.upsertAll(<ChatMessage>[local]);
    try {
      final response = await _api.sendText(
        sessionUnitId: sessionUnitId,
        clientMessageId: clientId,
        text: text,
        quoteMessageId: quote?.serverId,
        remindList: remindList,
      );
      final serverId =
          response['id'] is num
              ? (response['id'] as num).toInt()
              : int.tryParse('${response['id']}');
      local = local.copyWith(
        serverId: serverId,
        score: serverId == null ? local.score : serverId * 1000000,
        state: 'sent',
        raw: <String, dynamic>{
          ...local.raw,
          ...response,
          if (response['quoteMessage'] == null && quote != null)
            'quoteMessage': quote.raw,
        },
      );
    } catch (_) {
      local = local.copyWith(state: 'failed');
    }
    await _dao.upsertAll(<ChatMessage>[local]);
    if (local.state == 'sent') await _updateSessionSummary(local);
    return local;
  }

  Future<ChatMessage?> applyRealtimePayload({
    required int ownerId,
    required String sessionUnitId,
    required Object? payload,
  }) async {
    final json = _findRealtimeMessage(payload);
    if (json == null) return null;
    final payloadSessionId = firstNonEmpty(<Object?>[
      json['sessionUnitId'],
      asMap(json['sessionUnit'])['id'],
    ]);
    if (payloadSessionId.isNotEmpty && payloadSessionId != sessionUnitId) {
      return null;
    }
    final message = ChatMessage.fromJson(
      json,
      ownerId: ownerId,
      sessionUnitId: sessionUnitId,
    );
    // SignalR can replay the same durable message after a reconnect. Only a
    // previously unseen incoming message may increase the local unread badge.
    final wasPersisted =
        message.serverId != null &&
        await _dao.findByServerId(
              ownerId: ownerId,
              sessionUnitId: sessionUnitId,
              serverId: message.serverId!,
            ) !=
            null;
    await _dao.upsertAll(<ChatMessage>[message]);
    await _updateSessionSummary(
      message,
      incrementUnreadBadge: !message.isMine && !wasPersisted,
    );
    return message;
  }

  /// Stores a realtime message even when its chat page is not open. The
  /// session cache supplies the authoritative local owner association.
  Future<ChatMessage?> applyRealtimePayloadFromCachedSession(
    Object? payload, {
    String? sessionUnitId,
  }) async {
    final json = _findRealtimeMessage(payload);
    if (json == null) return null;
    final resolvedSessionUnitId =
        sessionUnitId ??
        firstNonEmpty(<Object?>[
          json['sessionUnitId'],
          asMap(json['sessionUnit'])['id'],
        ]);
    if (resolvedSessionUnitId.isEmpty) return null;
    final session = await _sessionDao?.readById(resolvedSessionUnitId);
    final ownerId = session?.ownerId;
    if (ownerId == null) return null;
    return applyRealtimePayload(
      ownerId: ownerId,
      sessionUnitId: resolvedSessionUnitId,
      payload: json,
    );
  }

  Future<ChatMessage> createLocalImage({
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
      messageType: 2,
      state: 'sending',
      score: maxScore + 1,
      createdAt: now,
      raw: <String, dynamic>{
        'messageType': 2,
        'creationTime': now.toIso8601String(),
        'content': <String, dynamic>{
          'fileName': file.name,
          'contentType': file.mimeType ?? 'image/jpeg',
          'size': file.size,
          'suffix': file.extension == null ? '' : '.${file.extension}',
          if (file.originalPath != null) 'path': file.originalPath,
        },
      },
    );
    await _dao.upsertAll(<ChatMessage>[message]);
    return message;
  }

  Future<ChatMessage> createLocalVideo({
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
      messageType: 4,
      state: 'sending',
      score: maxScore + 1,
      createdAt: now,
      raw: <String, dynamic>{
        'messageType': 4,
        'creationTime': now.toIso8601String(),
        'content': <String, dynamic>{
          'fileName': file.name,
          'contentType': file.mimeType ?? 'video/mp4',
          'size': file.size,
          'suffix': file.extension == null ? '' : '.${file.extension}',
          'url': file.originalUri.toString(),
          if (file.originalPath != null) 'path': file.originalPath,
        },
      },
    );
    await _dao.upsertAll(<ChatMessage>[message]);
    return message;
  }

  Future<ChatMessage> sendLocalImage({
    required ChatMessage local,
    required SelectedFile file,
    void Function(int sent, int total)? onProgress,
  }) => _sendLocalUpload(
    local: local,
    file: file,
    messageType: 2,
    onProgress: onProgress,
  );

  Future<ChatMessage> sendLocalVideo({
    required ChatMessage local,
    required SelectedFile file,
    void Function(int sent, int total)? onProgress,
  }) => _sendLocalUpload(
    local: local,
    file: file,
    messageType: 4,
    onProgress: onProgress,
  );

  Future<ChatMessage> _sendLocalUpload({
    required ChatMessage local,
    required SelectedFile file,
    required int messageType,
    void Function(int sent, int total)? onProgress,
  }) async {
    var result = local;
    try {
      final response = await _api.sendUploadFile(
        sessionUnitId: local.sessionUnitId,
        fileName: file.name,
        fileLength: file.size,
        openRead: file.readAsByteStream,
        messageType: messageType,
        onProgress: onProgress,
      );
      final serverId = asInt(response['id']);
      result = local.copyWith(
        serverId: serverId,
        score: serverId == null ? local.score : serverId * 1000000,
        state: 'sent',
        raw: <String, dynamic>{
          ...response,
          'messageType': messageType,
          'content': <String, dynamic>{
            ...local.content,
            ...asMap(response['content']),
          },
        },
      );
    } catch (error) {
      result = local.copyWith(
        state: 'failed',
        raw: <String, dynamic>{...local.raw, 'error': '$error'},
      );
    }
    await _dao.upsertAll(<ChatMessage>[result]);
    if (result.state == 'sent') await _updateSessionSummary(result);
    return result;
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

  Future<ChatMessage> createLocalVoice({
    required int ownerId,
    required String sessionUnitId,
    required SelectedFile file,
    required Duration duration,
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
      messageType: 3,
      state: 'sending',
      score: maxScore + 1,
      createdAt: now,
      raw: <String, dynamic>{
        'messageType': 3,
        'creationTime': now.toIso8601String(),
        'content': <String, dynamic>{
          'fileName': file.name,
          'contentType': file.mimeType ?? 'audio/mp4',
          'size': file.size,
          'time': duration.inMilliseconds,
          'suffix': file.extension == null ? '' : '.${file.extension}',
          if (file.originalPath != null) 'path': file.originalPath,
        },
      },
    );
    await _dao.upsertAll(<ChatMessage>[message]);
    debugPrint(
      '[sendVoice][local] session=$sessionUnitId localId=$clientId '
      'durationMs=${duration.inMilliseconds} state=sending',
    );
    return message;
  }

  Future<ChatMessage> sendLocalVoice({
    required ChatMessage local,
    required SelectedFile file,
    Duration? duration,
  }) async {
    var result = local;
    final resolvedDuration = duration ?? local.audioDuration;
    final durationSeconds =
        resolvedDuration.inSeconds <= 0 && resolvedDuration.inMilliseconds > 0
            ? (resolvedDuration.inMilliseconds / 1000).ceil()
            : resolvedDuration.inSeconds;
    try {
      final response = await _api.sendUploadFile(
        sessionUnitId: local.sessionUnitId,
        fileName: file.name,
        fileLength: file.size,
        openRead: file.readAsByteStream,
        messageType: 3,
        extraFields: <String, Object?>{'duration': durationSeconds},
      );
      final serverId =
          response['id'] is num
              ? (response['id'] as num).toInt()
              : int.tryParse('${response['id']}');
      result = local.copyWith(
        serverId: serverId,
        score: serverId == null ? local.score : serverId * 1000000,
        state: 'sent',
        raw: <String, dynamic>{
          ...response,
          'messageType': 3,
          'content': <String, dynamic>{
            ...local.content,
            ...?response['content'] as Map<String, dynamic>?,
            'duration': durationSeconds,
            'time': resolvedDuration.inMilliseconds,
          },
        },
      );
      debugPrint(
        '[sendVoice][remote] session=${local.sessionUnitId} '
        'localId=${local.localId} serverId=$serverId duration=$durationSeconds state=sent',
      );
    } catch (error) {
      result = local.copyWith(
        state: 'failed',
        raw: <String, dynamic>{...local.raw, 'error': '$error'},
      );
      debugPrint(
        '[sendVoice][failed] session=${local.sessionUnitId} '
        'localId=${local.localId} error=$error',
      );
    }
    await _dao.upsertAll(<ChatMessage>[result]);
    if (result.state == 'sent') await _updateSessionSummary(result);
    return result;
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

  Future<void> _updateSessionSummary(
    ChatMessage message, {
    bool incrementUnreadBadge = false,
  }) async {
    await _sessionDao?.updateLastMessage(
      ownerId: message.ownerId,
      sessionUnitId: message.sessionUnitId,
      score: message.score,
      message: message.raw,
      incrementUnreadBadge: incrementUnreadBadge,
    );
    _sessionChangeBus?.publish(
      ownerId: message.ownerId,
      sessionUnitId: message.sessionUnitId,
    );
  }

  int? _asInt(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value');
}

class MessagePage {
  const MessagePage(this.items, this.hasMore);
  final List<ChatMessage> items;
  final bool hasMore;
}

Map<String, dynamic>? _findRealtimeMessage(Object? value) {
  if (value is Map) {
    final map = Map<String, dynamic>.from(value);
    if (map['id'] != null &&
        (map['messageType'] != null || map['content'] != null)) {
      return map;
    }
    for (final child in map.values) {
      final found = _findRealtimeMessage(child);
      if (found != null) return found;
    }
  } else if (value is List) {
    for (final child in value) {
      final found = _findRealtimeMessage(child);
      if (found != null) return found;
    }
  }
  return null;
}
