import 'package:flutter/foundation.dart';

import '../datasources/session_dao.dart';
import '../datasources/session_unit_api.dart';
import '../models/session_summary.dart';
import '../models/logged_in_device.dart';
import '../models/chat_owner.dart';

class SessionRepository {
  SessionRepository({required SessionUnitApi api, required SessionDao dao})
    : _api = api,
      _dao = dao;

  final SessionUnitApi _api;
  final SessionDao _dao;

  Future<List<ChatOwner>> loadOwners() => _api.getOwners();

  Future<int?> readCurrentOwnerId() => _dao.readCurrentOwnerId();

  Future<void> saveCurrentOwnerId(int ownerId) =>
      _dao.writeCurrentOwnerId(ownerId);

  Future<List<LoggedInDevice>> loadDevices() async =>
      (await _api.getDevices()).items;

  Future<ChatOwner> resolveCurrentOwner() async {
    final owners = await _api.getOwners();
    if (owners.isEmpty) {
      throw StateError('当前账号没有可用的聊天对象');
    }
    return owners.first;
  }

  Future<LoadFriendsResult> loadFriends({
    required int ownerId,
    SessionCursor? cursor,
    int limit = 50,
  }) async {
    final localItems = await _dao.readPage(
      ownerId: ownerId,
      cursor: cursor,
      limit: limit,
    );
    debugPrint(
      '[loadFriends][local] ownerId=$ownerId cursor=${cursor?.id} '
      'requested=$limit added=${localItems.length}',
    );
    if (localItems.length >= limit) {
      debugPrint(
        '[loadFriends][result] source=local ownerId=$ownerId '
        'added=${localItems.length} hasMore=true',
      );
      return LoadFriendsResult(items: localItems, hasMore: true);
    }
    if (await _dao.isLoadedAll(ownerId)) {
      final totalCount = await _dao.count(ownerId);
      debugPrint(
        '[loadFriends][result] source=local ownerId=$ownerId '
        'added=${localItems.length} hasMore=false totalCount=$totalCount',
      );
      return LoadFriendsResult(
        items: localItems,
        hasMore: false,
        totalCount: totalCount,
      );
    }
    final last = localItems.isNotEmpty ? localItems.last : null;
    final maxMessageId = last?.lastMessageId ?? cursor?.maxMessageId;
    debugPrint(
      '[loadFriends][remote] ownerId=$ownerId '
      'maxMessageId=$maxMessageId maxScore=${last?.score ?? cursor?.score} '
      'cursorId=${last?.id ?? cursor?.id} '
      'requested=${limit - localItems.length}',
    );
    final remote = await _api.getFriends(
      ownerId: ownerId,
      maxResultCount: limit - localItems.length,
      maxMessageId: maxMessageId,
      maxScore: last?.score ?? cursor?.score,
      cursorId: last?.id ?? cursor?.id,
    );
    await _dao.upsertAll(remote.items);
    final hasMore = remote.items.length == limit - localItems.length;
    debugPrint(
      '[loadFriends][remote] ownerId=$ownerId received=${remote.items.length} '
      'persisted=${remote.items.length} hasMore=$hasMore '
      'totalCount=${remote.totalCount}',
    );
    if (!hasMore) await _dao.markLoadedAll(ownerId, true);
    final unique = <String, SessionSummary>{
      for (final item in localItems) item.id: item,
      for (final item in remote.items) item.id: item,
    };
    debugPrint(
      '[loadFriends][result] source=local+remote ownerId=$ownerId '
      'localAdded=${localItems.length} remoteAdded=${remote.items.length} '
      'pageAdded=${unique.length} hasMore=$hasMore',
    );
    return LoadFriendsResult(
      items: unique.values.toList(),
      hasMore: hasMore,
      totalCount: remote.totalCount,
    );
  }

  Future<List<SessionSummary>> loadLocalFriends({
    required int ownerId,
    SessionCursor? cursor,
    int limit = 50,
  }) => _dao.readPage(ownerId: ownerId, cursor: cursor, limit: limit);

  Future<List<SessionSummary>> loadChanges({required int ownerId}) async {
    final initialTicks = await _dao.readMaxTicks(ownerId);
    if (initialTicks == null || initialTicks <= 0) return const [];
    var minTicks = initialTicks;
    final changed = <String, SessionSummary>{};
    while (true) {
      final page = await _api.getChanges(ownerId: ownerId, minTicks: minTicks);
      if (page.items.isEmpty) break;
      for (final item in page.items) {
        changed[item.id] = item;
      }
      await _dao.upsertAll(page.items);
      final nextTicks = page.items
          .map((item) => item.ticks)
          .fold<int>(minTicks, (max, ticks) => ticks > max ? ticks : max);
      if (page.items.length < 99 || nextTicks <= minTicks) break;
      minTicks = nextTicks;
    }
    return changed.values.toList(growable: false);
  }
}

class LoadFriendsResult {
  const LoadFriendsResult({
    required this.items,
    required this.hasMore,
    this.totalCount,
  });
  final List<SessionSummary> items;
  final bool hasMore;
  final int? totalCount;
}
