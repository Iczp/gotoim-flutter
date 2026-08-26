import '../../../../core/database/unified_database.dart';
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

  Future<int?> readMaxTicks(int ownerId) =>
      _database.readMaxFriendTicks(ownerId);

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

  String _loadedAllKey(int ownerId) => 'friends-is-loaded-all-$ownerId';
}

class SessionCursor {
  const SessionCursor({required this.id, required this.score});
  final String id;
  final int score;
}
