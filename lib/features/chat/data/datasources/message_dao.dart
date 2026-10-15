import '../../../../core/database/unified_database.dart';
import '../models/chat_message.dart';

class MessageDao {
  MessageDao(this._database, {this.syncNamespace = ''});
  final UnifiedDatabase _database;
  final String syncNamespace;
  Future<void> resetSyncCursors(int owner) =>
      _database.resetMessageSyncCursors(syncNamespace, owner);
  Future<List<ChatMessage>> readByIds(
    int owner,
    String unit,
    List<int> ids,
  ) async {
    final result = <ChatMessage>[];
    for (var offset = 0; offset < ids.length; offset += 200) {
      result.addAll(
        (await _database.readMessageRowsByIds(
          owner,
          unit,
          ids.skip(offset).take(200).toList(),
        )).map(ChatMessage.fromDatabaseRow),
      );
    }
    return result;
  }

  Future<String?> syncCursor(int owner, String unit) =>
      _database.readMessageSyncCursor(syncNamespace, owner, unit);
  Future<List<String>> syncScopes(int owner, String after, int limit) =>
      _database.readMessageSyncScopes(owner, after, limit);
  Future<List<int>> syncIds(int owner, String unit, int after, int limit) =>
      _database.readMessageSyncIds(owner, unit, after, limit);
  Future<void> applySyncPage(
    int owner,
    String unit,
    List<Map<String, dynamic>> items, {
    String? cursor,
  }) => _database.applyMessageSyncPage(
    namespace: syncNamespace,
    owner: owner,
    unit: unit,
    items: items,
    cursor: cursor,
  );

  Future<void> markOpened(String localId) =>
      _database.markMessageOpened(localId);

  Future<void> deleteAll(Iterable<String> localIds) =>
      _database.deleteMessageRows(localIds);

  Future<List<ChatMessage>> readPage({
    required int ownerId,
    required String sessionUnitId,
    int? beforeScore,
    int limit = 30,
  }) async => (await _database.readMessageRows(
    ownerId: ownerId,
    sessionUnitId: sessionUnitId,
    beforeScore: beforeScore,
    limit: limit,
  )).map(ChatMessage.fromDatabaseRow).toList(growable: false);

  Future<ChatMessage?> findByServerId({
    required int ownerId,
    required String sessionUnitId,
    required int serverId,
  }) async {
    final row = await _database.readMessageRowByServerId(
      ownerId: ownerId,
      sessionUnitId: sessionUnitId,
      serverId: serverId,
    );
    return row == null ? null : ChatMessage.fromDatabaseRow(row);
  }

  Future<void> upsertAll(List<ChatMessage> messages) =>
      _database.upsertMessageRows(
        messages
            .map(
              (message) => {
                ...message.toDatabaseValues(),
                'syncNamespace': syncNamespace,
              },
            )
            .toList(growable: false),
      );

  Future<int> maxScore(int ownerId, String sessionUnitId) =>
      _database.readMaxMessageScore(ownerId, sessionUnitId);

  Future<int> maxServerId(int ownerId, String sessionUnitId) =>
      _database.readMaxMessageServerId(ownerId, sessionUnitId);

  Future<bool> isLoadedAll(String sessionUnitId) =>
      _database.readFriendMessagesLoadedAll(sessionUnitId);

  Future<void> markLoadedAll(String sessionUnitId, bool value) =>
      _database.writeFriendMessagesLoadedAll(sessionUnitId, value);
}
