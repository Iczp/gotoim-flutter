import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';

import '../../../../core/services/file/file_picker_service.dart';
import '../../../session/data/datasources/session_dao.dart';
import '../../../session/data/session_change_bus.dart';
import '../../../session/data/models/session_summary_helpers.dart';
import '../../../session/data/models/session_summary.dart';
import '../datasources/message_api.dart';
import '../datasources/message_dao.dart';
import '../models/chat_message.dart';

part 'message_repository_sync.dart';

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
  MessageApi get api => _api;
  final MessageDao _dao;
  final SessionDao? _sessionDao;
  final SessionChangeBus? _sessionChangeBus;
  final Map<String, Future<void>> _changeSyncInFlight = {};
  final Map<String, Future<List<ChatMessage>>> _latestInFlight = {};
  final Map<String, Timer> _latestRetries = {};
  bool _disposed = false;

  void dispose() {
    _disposed = true;
    for (final timer in _latestRetries.values) {
      timer.cancel();
    }
    _latestRetries.clear();
  }

  void _checkActive() {
    if (_disposed) throw StateError('Message synchronization context expired');
  }

  DateTime? _changeSyncRetryAt;
  bool get isChangeSyncAvailable =>
      _changeSyncRetryAt?.isAfter(DateTime.now()) != true;
  Future<String?> changeSyncCursor(int owner, String unit) =>
      _dao.syncCursor(owner, unit);
  Future<List<ChatMessage>> loadLocalByIds(
    int owner,
    String unit,
    List<int> ids,
  ) => _dao.readByIds(owner, unit, ids);

  Future<void> markOpened(String localId) => _dao.markOpened(localId);
  Future<void> deleteLocal(Iterable<String> localIds) =>
      _dao.deleteAll(localIds);

  Future<void> sendTyping({
    required String sessionUnitId,
    required String sessionId,
    String? senderName,
    required bool isTyping,
    String action = 'typing',
    String? actionText,
  }) => _api.sendTyping(
    sessionUnitId: sessionUnitId,
    sessionId: sessionId,
    senderName: senderName,
    isTyping: isTyping,
    action: action,
    actionText: actionText,
  );

  Future<Map<String, dynamic>?> getPublishedOfficialMenus(
    int chatObjectId, {
    String? version,
  }) =>
      _api.getPublishedOfficialMenus(chatObjectId, version: version);

  Future<void> triggerOfficialMenu({
    required String menuId,
    required String sessionUnitId,
  }) => _api.triggerOfficialMenu(
    menuId: menuId,
    sessionUnitId: sessionUnitId,
  );

  Future<void> reportMenuClick({
    required String menuId,
    String? sessionUnitId,
    int? senderId,
  }) => _api.reportMenuClick(
    menuId: menuId,
    sessionUnitId: sessionUnitId,
    senderId: senderId,
  );

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

  Future<ChatMessage?> findAnyByServerId(int serverId) =>
      _dao.findAnyByServerId(serverId);

  Future<ChatMessage?> fetchAndApplyUpdatedMessage({
    required int ownerId,
    required String sessionUnitId,
    required int messageId,
  }) async {
    try {
      final json = await _api.getItem(
        sessionUnitId: sessionUnitId,
        messageId: messageId,
      );
      final remoteMessage = ChatMessage.fromJson(
        json,
        ownerId: ownerId,
        sessionUnitId: sessionUnitId,
      );
      final existing = await _dao.findByServerId(
        ownerId: ownerId,
        sessionUnitId: sessionUnitId,
        serverId: messageId,
      );
      final merged =
          existing != null
              ? existing.copyWith(
                serverId: remoteMessage.serverId,
                score: remoteMessage.score,
                raw: <String, dynamic>{
                  ...existing.raw,
                  ...remoteMessage.raw,
                  'content': <String, dynamic>{
                    ...existing.content,
                    ...remoteMessage.content,
                  },
                },
              )
              : remoteMessage;
      _checkActive();
      await _dao.upsertAll(<ChatMessage>[merged]);
      await _updateSessionSummary(merged);
      _sessionChangeBus?.publish(
        ownerId: ownerId,
        sessionUnitId: sessionUnitId,
        messageIds: <int>[messageId],
      );
      return merged;
    } catch (e) {
      debugPrint('[MessageRepository] fetchAndApplyUpdatedMessage failed: $e');
      return null;
    }
  }

  Future<int> maxLocalServerId({
    required int ownerId,
    required String sessionUnitId,
  }) => _dao.maxServerId(ownerId, sessionUnitId);

  /// Returns the safe cursor for pulling new messages.
  /// Prefers the contiguous sync watermark if established; returns 0 if not yet established.
  /// F1: Never blindly promote maxServerId to watermark, as an out-of-order realtime message
  /// or send receipt would cause un-synced gaps to be skipped.
  Future<int> getLatestSyncCursor({
    required int ownerId,
    required String sessionUnitId,
  }) async {
    final watermark = await _dao.readMessageWatermark(ownerId, sessionUnitId);
    if (watermark != null && watermark > 0) {
      return watermark;
    }
    return 0;
  }

  Future<void> updateMessageWatermark({
    required int ownerId,
    required String sessionUnitId,
    required int watermark,
  }) async {
    if (watermark > 0) {
      _checkActive();
      await _dao.writeMessageWatermark(ownerId, sessionUnitId, watermark);
    }
  }

  /// Retries a failed text message in-place so its local identity and UI slot
  /// remain stable instead of inserting a duplicate bubble.
  Future<ChatMessage> retryText(ChatMessage message) async {
    if (message.messageType != 0 || message.state == 'sending') return message;
    var result = message.copyWith(state: 'sending');
    _checkActive();
    await _dao.upsertAll(<ChatMessage>[result]);
    await _updateSessionSummary(result);
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
    } catch (error) {
      result = result.copyWith(
        state: 'failed',
        raw: <String, dynamic>{
          ...result.raw,
          'errorMessage': '$error',
          'error': '$error',
        },
      );
    }
    _checkActive();
    await _dao.upsertAll(<ChatMessage>[result]);
    await _updateSessionSummary(result);
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
    _checkActive();
    await _dao.applySyncPage(message.ownerId, message.sessionUnitId, [
      {'messageId': message.serverId, 'syncVersion': 0, 'isDeleted': true},
    ]);
    _sessionChangeBus?.publish(
      ownerId: message.ownerId,
      sessionUnitId: message.sessionUnitId,
      messageIds: [message.serverId!],
      deletedMessageIds: [message.serverId!],
    );
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
    _checkActive();
    await _dao.upsertAll(<ChatMessage>[updated]);
    await _updateSessionSummary(updated);
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
        if (remindList != null && remindList.isNotEmpty)
          'remindList': remindList,
      },
    );
    _checkActive();
    await _dao.upsertAll(<ChatMessage>[localMessage]);
    // 立即通知会话列表更新为发送中状态
    await _updateSessionSummary(localMessage);

    var result = localMessage;
    debugPrint(
      '[MessageRepository.sendLink] 发送链接消息请求 -> sessionUnitId: $sessionUnitId, '
      'ownerId: $ownerId, clientMessageId: $clientMessageId, url: $url, title: $title',
    );
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
      debugPrint(
        '[MessageRepository.sendLink] 链接消息发送成功 -> sessionUnitId: $sessionUnitId, serverId: $serverId',
      );
    } catch (e, st) {
      debugPrint(
        '[MessageRepository.sendLink] 链接消息发送失败 -> sessionUnitId: $sessionUnitId, error: $e\n$st',
      );
      result = result.copyWith(
        state: 'failed',
        raw: <String, dynamic>{
          ...result.raw,
          'errorMessage': '$e',
          'error': '$e',
        },
      );
    }
    _checkActive();
    await _dao.upsertAll(<ChatMessage>[result]);
    await _updateSessionSummary(result);
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
    _checkActive();
    final covered = await _dao.readHistoryCoverage(
      ownerId,
      sessionUnitId,
      beforeScore,
    );
    if (covered != null &&
        (beforeScore != null || local.isNotEmpty) &&
        (local.length >= limit || covered['earliest'] == true)) {
      final lowest = local.isEmpty ? 0 : local.last.serverId ?? 0;
      final highest = local.where((m) => m.serverId != null)
          .fold<int>(0, (max, m) => m.serverId! > max ? m.serverId! : max);
      final withinUpper = beforeScore != null ||
          highest <= (covered['max'] as int? ?? 0);
      if (withinUpper && (covered['earliest'] == true || lowest >= (covered['min'] as int))) {
        return MessagePage(
          local,
          covered['earliest'] != true || local.length >= limit,
        );
      }
    }
    // Query from the requested boundary, never from the oldest isolated cache row.
    final maxMessageId = beforeScore == null ? null : beforeScore ~/ 1000000;
    try {
      final remote = await _api.history(
        ownerId: ownerId,
        sessionUnitId: sessionUnitId,
        limit: limit,
        maxMessageId: maxMessageId == 0 ? null : maxMessageId,
      );
      _checkActive();
      _checkActive();
      await _dao.upsertAll(remote.items);
      final hasMore = remote.hasMore ?? remote.items.length >= limit;
      if (!hasMore) await _dao.markLoadedAll(sessionUnitId, true);
      await _dao.writeHistoryCoverage(ownerId, sessionUnitId, beforeScore, {
        'min': remote.items
            .map((m) => m.serverId ?? 0)
            .fold<int>(0, (a, b) => a == 0 || b < a ? b : a),
        'max': remote.items.fold<int>(0, (max, m) =>
            (m.serverId ?? 0) > max ? m.serverId! : max),
        'earliest': !hasMore,
      });
      debugPrint(
        '[loadMessages][remote] session=$sessionUnitId maxMessageId=$maxMessageId '
        'received=${remote.items.length} persisted=${remote.items.length}',
      );
      final all = await _dao.readPage(
        ownerId: ownerId,
        sessionUnitId: sessionUnitId,
        beforeScore: beforeScore,
        limit: limit,
      );
      final ids = remote.items.map((m) => m.serverId).toSet();
      return MessagePage(
        all
            .where((m) => m.serverId == null || ids.contains(m.serverId))
            .toList(),
        hasMore,
      );
    } catch (error) {
      debugPrint(
        '[loadHistory][ERROR] session=$sessionUnitId '
        'maxMessageId=$maxMessageId error=$error',
      );
      if (error is ApiException && error.statusCode == 403) {
        // F7: Forbidden (403): Server denied history access for this sessionUnit.
        // Return local messages without permanently marking loadedAll in SQLite,
        // so that once permissions are restored, future queries can retry cleanly.
        debugPrint(
          '[loadHistory][403] session=$sessionUnitId Forbidden; returning local without marking loadedAll',
        );
        return MessagePage(local, false);
      }
      if (local.isNotEmpty) return MessagePage(local, true);
      rethrow;
    }
  }

  Future<MessageSliceResult> getAroundAnchorSlice({
    required int ownerId,
    required String sessionUnitId,
    required int targetServerId,
    int beforeCount = 20,
    int afterCount = 20,
  }) async {
    // 1. 本地优先查找切片
    var slice = await _dao.readAroundAnchorSlice(
      ownerId: ownerId,
      sessionUnitId: sessionUnitId,
      targetServerId: targetServerId,
      beforeCount: beforeCount,
      afterCount: afterCount,
    );

    ChatMessage? anchor = slice['anchor'] as ChatMessage?;
    var before = slice['before'] as List<ChatMessage>? ?? const [];
    var after = slice['after'] as List<ChatMessage>? ?? const [];

    // 2. 若本地无锚点消息，穿透拉取
    if (anchor == null) {
      try {
        final olderRemote = await _api.history(
          ownerId: ownerId,
          sessionUnitId: sessionUnitId,
          limit: beforeCount + 1,
          maxMessageId: targetServerId,
        );
        _checkActive();
        if (olderRemote.items.isNotEmpty) {
          await _dao.upsertAll(olderRemote.items);
        }

        final newerRemote = await _api.latest(
          ownerId: ownerId,
          sessionUnitId: sessionUnitId,
          limit: afterCount + 1,
          minMessageId: targetServerId,
        );
        _checkActive();
        if (newerRemote.items.isNotEmpty) {
          await _dao.upsertAll(newerRemote.items);
        }

        slice = await _dao.readAroundAnchorSlice(
          ownerId: ownerId,
          sessionUnitId: sessionUnitId,
          targetServerId: targetServerId,
          beforeCount: beforeCount,
          afterCount: afterCount,
        );
        anchor = slice['anchor'] as ChatMessage?;
        before = slice['before'] as List<ChatMessage>? ?? const [];
        after = slice['after'] as List<ChatMessage>? ?? const [];
      } catch (e) {
        debugPrint('[getAroundAnchorSlice] remote fetch error: $e');
      }
    }

    final hasMoreOlder = before.length > beforeCount;
    final validBefore = hasMoreOlder ? before.take(beforeCount).toList() : before;
    final hasMoreNewer = after.length > afterCount;
    final validAfter = hasMoreNewer ? after.take(afterCount).toList() : after;

    final chronologicalBefore = validBefore.reversed.toList();
    final combined = <ChatMessage>[
      ...chronologicalBefore,
      if (anchor != null) anchor,
      ...validAfter,
    ];

    final targetIndex = anchor == null ? -1 : chronologicalBefore.length;

    return MessageSliceResult(
      items: combined,
      anchor: anchor,
      targetIndex: targetIndex,
      hasMoreOlder: hasMoreOlder,
      hasMoreNewer: hasMoreNewer,
    );
  }

  Future<MessagePage> loadNewerMessages({
    required int ownerId,
    required String sessionUnitId,
    required int afterScore,
    required int afterServerId,
    int limit = 30,
  }) async {
    final local = await _dao.readNewerPage(
      ownerId: ownerId,
      sessionUnitId: sessionUnitId,
      afterScore: afterScore,
      limit: limit,
    );

    if (local.length >= limit) {
      return MessagePage(local, true);
    }

    try {
      final remote = await _api.latest(
        ownerId: ownerId,
        sessionUnitId: sessionUnitId,
        limit: limit,
        minMessageId: afterServerId,
      );
      _checkActive();
      if (remote.items.isNotEmpty) {
        await _dao.upsertAll(remote.items);
      }
      final refreshed = await _dao.readNewerPage(
        ownerId: ownerId,
        sessionUnitId: sessionUnitId,
        afterScore: afterScore,
        limit: limit,
      );
      final hasMore = remote.hasMore ?? remote.items.length >= limit;
      return MessagePage(refreshed, hasMore);
    } catch (e) {
      return MessagePage(local, false);
    }
  }

  Future<List<ChatMessage>> loadLatest({
    required int ownerId,
    required String sessionUnitId,
    required int minMessageId,
    int limit = 99,
    int maxPages = 10,
    bool refreshRecent = false,
  }) async {
    _checkActive();
    final key = '$ownerId:$sessionUnitId';
    _latestRetries.remove(key)?.cancel();
    final existing = _latestInFlight[key];
    if (existing != null) return existing;
    final task = _loadLatest(
      ownerId: ownerId,
      sessionUnitId: sessionUnitId,
      minMessageId: minMessageId,
      limit: limit,
      maxPages: maxPages,
      refreshRecent: refreshRecent,
    );
    _latestInFlight[key] = task;
    try {
      return await task;
    } catch (error) {
      if (!_disposed && !(error is ApiException &&
          (error.statusCode == 401 || error.statusCode == 403))) {
        _scheduleLatest(ownerId, sessionUnitId, minMessageId, limit, maxPages,
            delay: const Duration(seconds: 5));
      }
      rethrow;
    } finally {
      if (identical(_latestInFlight[key], task)) _latestInFlight.remove(key);
    }
  }

  void _scheduleLatest(
    int owner,
    String unit,
    int cursor,
    int limit,
    int pages, {
    Duration delay = const Duration(milliseconds: 100),
  }) {
    if (_disposed) return;
    final key = '$owner:$unit';
    _latestRetries.remove(key)?.cancel();
    _latestRetries[key] = Timer(delay, () async {
      _latestRetries.remove(key);
      if (_disposed) return;
      try {
        await loadLatest(
          ownerId: owner,
          sessionUnitId: unit,
          minMessageId: cursor,
          limit: limit,
          maxPages: pages,
        );
      } catch (error) {
        debugPrint('[MessageSync] continuation failed: $error');
        _scheduleLatest(
          owner,
          unit,
          cursor,
          limit,
          pages,
          delay: const Duration(seconds: 5),
        );
      }
    });
  }

  Future<List<ChatMessage>> _loadLatest({
    required int ownerId,
    required String sessionUnitId,
    required int minMessageId,
    required int limit,
    required int maxPages,
    required bool refreshRecent,
  }) async {
    if (limit < 1 || maxPages < 1) {
      throw ArgumentError('Invalid sync batch size');
    }
    var cursor = minMessageId;
    final collected = <String, ChatMessage>{};
    var hasMore = false;
    final startedEmpty = minMessageId == 0 &&
        await _dao.maxServerId(ownerId, sessionUnitId) == 0;
    if (refreshRecent) {
      // Withdrawals do not create a larger message ID. Refresh a bounded
      // recent window as well as the forward cursor on re-entry/reconnect.
      final recent = await _api.history(
        ownerId: ownerId,
        sessionUnitId: sessionUnitId,
        limit: limit,
      );
      for (final item in recent.items) {
        collected[item.localId] = item;
      }
      _checkActive();
      if (startedEmpty && await _dao.maxServerId(ownerId, sessionUnitId) == 0) {
        cursor = recent.items.fold<int>(0, (max, m) =>
            (m.serverId ?? 0) > max ? m.serverId! : max);
      }
    }
    var forwardWatermark = cursor;
    for (var pageIndex = 0; pageIndex < maxPages; pageIndex++) {
      final page = await _api.latest(
        ownerId: ownerId,
        sessionUnitId: sessionUnitId,
        limit: limit,
        minMessageId: cursor,
      );
      _checkActive();
      hasMore = page.hasMore ?? page.items.length >= limit;
      if (page.items.isEmpty) {
        if (hasMore) throw StateError('Empty message page with more results');
        break;
      }
      if (page.items.any((m) => m.serverId == null || m.serverId! <= cursor)) {
        throw StateError('Message page did not advance');
      }
      for (final item in page.items) {
        collected[item.localId] = item;
      }
      final next = page.items
          .map((item) => item.serverId ?? 0)
          .fold<int>(cursor, (max, id) => id > max ? id : max);
      forwardWatermark = next;
      if (!hasMore || next <= cursor) break;
      cursor = next;
    }
    final items = collected.values.toList(growable: false);
    _checkActive();
    _checkActive();
    await _dao.upsertAll(items);

    // F2: Separate forward progress and snapshot coverage.
    // Watermark ONLY advances through confirmed forward latest pages!
    // Never jump forwardWatermark based on recent snapshot when minMessageId > 0!
    if (forwardWatermark > minMessageId) {
      _checkActive();
      await _dao.writeMessageWatermark(
        ownerId,
        sessionUnitId,
        forwardWatermark,
      );
    }
    if (hasMore) {
      _scheduleLatest(
        ownerId,
        sessionUnitId,
        forwardWatermark,
        limit,
        maxPages,
      );
    }
    final persisted =
        items.isEmpty
            ? const <ChatMessage>[]
            : (await _dao.readPage(
                  ownerId: ownerId,
                  sessionUnitId: sessionUnitId,
                  limit: limit + items.length,
                ))
                .where(
                  (item) => collected.values.any(
                    (incoming) => incoming.serverId == item.serverId,
                  ),
                )
                .toList(growable: false);
    final persistedMaxMessageId = await _dao.maxServerId(
      ownerId,
      sessionUnitId,
    );
    if (persisted.isNotEmpty) {
      final newest = [...persisted]
        ..sort((a, b) => (b.serverId ?? 0).compareTo(a.serverId ?? 0));
      await _updateSessionSummary(newest.first);
    }
    debugPrint(
      '[loadMessages][latest] session=$sessionUnitId minMessageId=$minMessageId '
      'received=${items.length} persistedMaxMessageId=$persistedMaxMessageId',
    );
    return persisted;
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
    _checkActive();
    await _dao.upsertAll(<ChatMessage>[local]);
    // 立即通知会话列表更新为发送中状态
    await _updateSessionSummary(local);
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
    } catch (error) {
      local = local.copyWith(
        state: 'failed',
        raw: <String, dynamic>{
          ...local.raw,
          'errorMessage': '$error',
          'error': '$error',
        },
      );
    }
    _checkActive();
    await _dao.upsertAll(<ChatMessage>[local]);
    await _updateSessionSummary(local);
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
    final incoming = ChatMessage.fromJson(
      json,
      ownerId: ownerId,
      sessionUnitId: sessionUnitId,
    );
    // SignalR can replay the same durable message after a reconnect. Only a
    // previously unseen incoming message may increase the local unread badge.
    final existing =
        incoming.serverId != null
            ? await _dao.findByServerId(
              ownerId: ownerId,
              sessionUnitId: sessionUnitId,
              serverId: incoming.serverId!,
            )
            : null;
    // Withdrawal events contain identity and state, not the original content.
    // Preserve the local row, sender, timestamp and media metadata.
    if (incoming.isRollbacked && existing == null) {
      // A notification cannot make a locally deleted or never-loaded message
      // visible again. The authoritative history API supplies visible rows.
      final friend = await _sessionDao?.readById(sessionUnitId);
      final last = asMap(friend?.raw['lastMessage']);
      if (incoming.serverId != null &&
          _asInt(last['id'] ?? last['messageId']) == incoming.serverId) {
        await _updateSessionSummary(incoming);
      }
      return null;
    }
    final message =
        existing != null && incoming.isRollbacked
            ? existing.copyWith(
              raw: <String, dynamic>{
                ...existing.raw,
                'isRollbacked': true,
                'rollbackTime':
                    json['rollbackTime'] ?? existing.raw['rollbackTime'],
              },
            )
            : existing?.isRollbacked == true
            ? existing!
            : incoming;
    _checkActive();
    await _dao.upsertAll(<ChatMessage>[message]);
    final persisted =
        message.serverId == null
            ? message
            : await _dao.findByServerId(
                  ownerId: ownerId,
                  sessionUnitId: sessionUnitId,
                  serverId: message.serverId!,
                ) ??
                message;
    await _updateSessionSummary(
      persisted,
      incrementUnreadBadge:
          !persisted.isMine && existing == null && !persisted.isRollbacked,
    );
    return persisted;
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
    int? width,
    int? height,
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
          if (width != null && width > 0) 'width': width,
          if (height != null && height > 0) 'height': height,
        },
      },
    );
    _checkActive();
    await _dao.upsertAll(<ChatMessage>[message]);
    await _updateSessionSummary(message);
    return message;
  }

  Future<ChatMessage> createLocalVideo({
    required int ownerId,
    required String sessionUnitId,
    required SelectedFile file,
    int? width,
    int? height,
    int? durationMs,
    String? localThumbnailPath,
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
          if (width != null && width > 0) 'width': width,
          if (height != null && height > 0) 'height': height,
          if (durationMs != null && durationMs > 0) 'duration': durationMs / 1000.0,
          if (durationMs != null && durationMs > 0) 'durationMs': durationMs,
          if (localThumbnailPath != null && localThumbnailPath.isNotEmpty)
            'localThumbnailPath': localThumbnailPath,
        },
      },
    );
    _checkActive();
    await _dao.upsertAll(<ChatMessage>[message]);
    await _updateSessionSummary(message);
    return message;
  }

  Future<ChatMessage> sendLocalImage({
    required ChatMessage local,
    required SelectedFile file,
    Map<String, Object?>? extraFields,
    void Function(int sent, int total)? onProgress,
  }) => _sendLocalUpload(
    local: local,
    file: file,
    messageType: 2,
    extraFields: extraFields,
    onProgress: onProgress,
  );

  Future<ChatMessage> sendLocalVideo({
    required ChatMessage local,
    required SelectedFile file,
    Map<String, Object?>? extraFields,
    Map<String, MultipartUploadFile>? extraFiles,
    void Function(int sent, int total)? onProgress,
  }) => _sendLocalUpload(
    local: local,
    file: file,
    messageType: 4,
    extraFields: extraFields,
    extraFiles: extraFiles,
    onProgress: onProgress,
  );

  Future<ChatMessage> _sendLocalUpload({
    required ChatMessage local,
    required SelectedFile file,
    required int messageType,
    Map<String, Object?>? extraFields,
    Map<String, MultipartUploadFile>? extraFiles,
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
        extraFields: extraFields,
        extraFiles: extraFiles,
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
        raw: <String, dynamic>{
          ...local.raw,
          'errorMessage': '$error',
          'error': '$error',
        },
      );
    }
    _checkActive();
    await _dao.upsertAll(<ChatMessage>[result]);
    await _updateSessionSummary(result);
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
    _checkActive();
    await _dao.upsertAll(<ChatMessage>[message]);
    await _updateSessionSummary(message);
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
    _checkActive();
    await _dao.upsertAll(<ChatMessage>[message]);
    await _updateSessionSummary(message);
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
        extraFields: <String, Object?>{
          'durationMs': resolvedDuration.inMilliseconds,
        },
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
        raw: <String, dynamic>{
          ...local.raw,
          'errorMessage': '$error',
          'error': '$error',
        },
      );
      debugPrint(
        '[sendVoice][failed] session=${local.sessionUnitId} '
        'localId=${local.localId} error=$error',
      );
    }
    _checkActive();
    await _dao.upsertAll(<ChatMessage>[result]);
    await _updateSessionSummary(result);
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
        raw: <String, dynamic>{
          ...local.raw,
          'errorMessage': '$error',
          'error': '$error',
        },
      );
      debugPrint(
        '[sendFile][failed] session=${local.sessionUnitId} '
        'localId=${local.localId} error=$error',
      );
    }
    _checkActive();
    await _dao.upsertAll(<ChatMessage>[result]);
    await _updateSessionSummary(result);
    return result;
  }

  Future<void> _updateSessionSummary(
    ChatMessage message, {
    bool incrementUnreadBadge = false,
  }) async {
    final rawMessage = Map<String, dynamic>.from(message.raw);
    rawMessage['state'] = message.state;
    rawMessage['clientMessageId'] = message.clientMessageId;
    rawMessage['messageType'] = message.messageType;
    await _sessionDao?.updateLastMessage(
      ownerId: message.ownerId,
      sessionUnitId: message.sessionUnitId,
      message: rawMessage,
      incrementUnreadBadge: incrementUnreadBadge,
    );
    _sessionChangeBus?.publish(
      ownerId: message.ownerId,
      sessionUnitId: message.sessionUnitId,
      messageId: message.serverId,
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

class MessageSliceResult {
  const MessageSliceResult({
    required this.items,
    required this.anchor,
    required this.targetIndex,
    required this.hasMoreOlder,
    required this.hasMoreNewer,
  });

  final List<ChatMessage> items;
  final ChatMessage? anchor;
  final int targetIndex;
  final bool hasMoreOlder;
  final bool hasMoreNewer;
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
