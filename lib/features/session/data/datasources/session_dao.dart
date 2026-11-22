import '../../../../core/database/unified_database.dart';
import '../../../chat_settings/data/models/chat_member.dart';
import '../models/chat_owner.dart';
import '../models/session_summary.dart';

/// Local session-list access backed by the shared Friends table.
class SessionDao {
  SessionDao(this._database);

  final UnifiedDatabase _database;

  Future<List<SessionSummary>> readPage({
    required int ownerId,
    SessionCursor? cursor,
    int limit = 50,
  }) async {
    final rows = await _database.readFriendRows(
      ownerId: ownerId,
      cursorScore: cursor?.score,
      cursorId: cursor?.id,
      limit: limit,
    );
    final sessions = <SessionSummary>[];
    for (final row in rows) {
      try {
        final session = SessionSummary.fromDatabaseRow(row);
        if (session.id.isNotEmpty) sessions.add(session);
      } on FormatException {
        // A stale/corrupt cache record must not prevent the remaining list
        // from being shown. The next HTTP sync will repair valid records.
      }
    }
    return sessions;
  }

  Future<SessionSummary?> readById(String id) async {
    final row = await _database.readFriendRow(id);
    if (row == null) return null;
    try {
      return SessionSummary.fromDatabaseRow(row);
    } on FormatException {
      return null;
    }
  }

  Future<int?> readMaxTicks(int ownerId) =>
      _database.readMaxFriendTicks(ownerId);

  Future<int> repairScores(int ownerId) =>
      _database.repairFriendScores(ownerId);

  Future<int> count(int ownerId) => _database.countFriendRows(ownerId);

  Future<List<ChatOwner>> readOwners() async =>
      (await _database.readOwnerRows())
          .map(ChatOwner.fromDatabaseRow)
          .toList(growable: false);

  Future<void> upsertOwners(List<ChatOwner> owners) =>
      _database.upsertOwnerRows(
        owners.map((owner) => owner.toDatabaseValues()).toList(growable: false),
      );

  Future<bool> isLoadedAll(int ownerId) async =>
      await _database.readSettingValue(_loadedAllKey(ownerId)) == 'true';

  Future<void> markLoadedAll(int ownerId, bool value) =>
      _database.writeSettingValue(
        id: _loadedAllKey(ownerId),
        group: 'friends',
        value: '$value',
      );

  Future<int?> readCurrentOwnerId() async => int.tryParse(
    await _database.readSettingValue('owners-current-owner-id') ?? '',
  );

  Future<void> writeCurrentOwnerId(int ownerId) => _database.writeSettingValue(
    id: 'owners-current-owner-id',
    group: 'owners',
    value: '$ownerId',
  );

  Future<void> upsertAll(List<SessionSummary> sessions) =>
      _database.upsertFriendRows(
        sessions.map((session) => session.toDatabaseValues()).toList(),
      );

  Future<void> updateLastMessage({
    required int ownerId,
    required String sessionUnitId,
    required Map<String, dynamic> message,
    bool incrementUnreadBadge = false,
  }) => _database.updateFriendLastMessage(
    ownerId: ownerId,
    sessionUnitId: sessionUnitId,
    message: message,
    incrementUnreadBadge: incrementUnreadBadge,
  );

  Future<int> resetMessages(int ownerId, String sessionUnitId) =>
      _database.resetFriendMessages(ownerId, sessionUnitId);

  Future<int> deleteFriend(String sessionUnitId) =>
      _database.deleteFriendRow(sessionUnitId);

  Future<int> deleteMessages(int ownerId, String sessionUnitId) =>
      _database.deleteMessagesBySessionUnit(ownerId, sessionUnitId);

  Future<int> markKilled(String sessionUnitId) =>
      _database.markFriendKilled(sessionUnitId);

  Future<int> markActive(String sessionUnitId) =>
      _database.markFriendActive(sessionUnitId);

  Future<String?> readSettingValue(String key) =>
      _database.readSettingValue(key);

  Future<void> writeSettingValue({
    required String id,
    required String group,
    required String value,
  }) =>
      _database.writeSettingValue(id: id, group: group, value: value);

  Future<int> deleteMember({required String sessionUnitId, required String memberId}) =>
      _database.deleteMemberRow(sessionUnitId: sessionUnitId, memberId: memberId);

  Future<void> upsertMember(int ownerId, String sessionUnitId, Map<String, dynamic> rawMember) async {
    final member = ChatMember.fromJson(rawMember);
    await _database.upsertMemberRows([member.toDatabaseValues(ownerId, sessionUnitId)]);
  }

  String _loadedAllKey(int ownerId) => 'friends-is-loaded-all-$ownerId';
}

class SessionCursor {
  const SessionCursor({
    required this.id,
    required this.score,
    this.maxMessageId,
  });
  final String id;
  final int score;
  final int? maxMessageId;
}
