import '../../../../core/database/unified_database.dart';
import '../models/session_summary.dart';

/// Local session-list access backed by the shared Friends table.
class SessionDao {
  SessionDao(this._database);

  final UnifiedDatabase _database;

  Future<List<SessionSummary>> readRecent({int limit = 50}) async {
    final rows = await _database.readFriendRows(limit: limit);
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

  Future<void> upsertAll(List<SessionSummary> sessions) =>
      _database.upsertFriendRows(
        sessions.map((session) => session.toDatabaseValues()).toList(),
      );
}
