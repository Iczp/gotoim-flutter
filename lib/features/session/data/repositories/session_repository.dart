import '../datasources/session_dao.dart';
import '../datasources/session_unit_api.dart';
import '../models/session_summary.dart';
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
    if (localItems.length >= limit) {
      return LoadFriendsResult(items: localItems, hasMore: true);
    }
    if (await _dao.isLoadedAll(ownerId)) {
      return LoadFriendsResult(items: localItems, hasMore: false);
    }
    final last = localItems.isNotEmpty ? localItems.last : null;
    final remote = await _api.getFriends(
      ownerId: ownerId,
      maxResultCount: limit - localItems.length,
      maxScore: last?.score ?? cursor?.score,
      cursorId: last?.id ?? cursor?.id,
    );
    await _dao.upsertAll(remote.items);
    final hasMore = remote.items.length == limit - localItems.length;
    if (!hasMore) await _dao.markLoadedAll(ownerId, true);
    final unique = <String, SessionSummary>{
      for (final item in localItems) item.id: item,
      for (final item in remote.items) item.id: item,
    };
    return LoadFriendsResult(items: unique.values.toList(), hasMore: hasMore);
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
  const LoadFriendsResult({required this.items, required this.hasMore});
  final List<SessionSummary> items;
  final bool hasMore;
}
