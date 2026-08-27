import '../../../../core/database/unified_database.dart';
import '../models/chat_member.dart';

class ChatMemberDao {
  ChatMemberDao(this._database);
  final UnifiedDatabase _database;

  Future<List<ChatMember>> readPage({
    required int ownerId,
    required String sessionUnitId,
    int? cursorScore,
    String? cursorId,
    int limit = 50,
    String keyword = '',
  }) async => (await _database.readMemberRows(
    ownerId: ownerId,
    sessionUnitId: sessionUnitId,
    cursorScore: cursorScore,
    cursorId: cursorId,
    limit: limit,
    keyword: keyword,
  )).map(ChatMember.fromDatabaseRow).toList(growable: false);

  Future<void> upsertAll(
    int ownerId,
    String sessionUnitId,
    List<ChatMember> items,
  ) => _database.upsertMemberRows(
    items.map((item) => item.toDatabaseValues(ownerId, sessionUnitId)).toList(),
  );

  Future<void> updateState(
    String sessionUnitId, {
    int? totalCount,
    bool? loadedAll,
  }) => _database.updateFriendMemberState(
    sessionUnitId: sessionUnitId,
    memberCount: totalCount,
    loadedAll: loadedAll,
  );

  Future<bool> isLoadedAll(String sessionUnitId) =>
      _database.readFriendMembersLoadedAll(sessionUnitId);

  Future<int> clearMessages(int ownerId, String sessionUnitId) =>
      _database.resetFriendMessages(ownerId, sessionUnitId);
}
