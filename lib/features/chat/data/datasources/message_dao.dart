import 'dart:convert';
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

  Future<int?> readMessageWatermark(int ownerId, String sessionUnitId) async {
    final raw = await syncCursor(ownerId, sessionUnitId);
    if (raw == null || raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  Future<void> writeMessageWatermark(
    int ownerId,
    String sessionUnitId,
    int watermark,
  ) => _database.writeMessageSyncCursor(
    syncNamespace,
    ownerId,
    sessionUnitId,
    watermark.toString(),
  );
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

  String _historyKey(int owner, String unit, int? before) =>
      'message-history:v2:$syncNamespace:$owner:$unit:${before ?? "head"}';

  Future<Map<String, dynamic>?> readHistoryCoverage(
    int owner,
    String unit,
    int? before,
  ) async {
    final raw = await _database.readSettingValue(
      _historyKey(owner, unit, before),
    );
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeHistoryCoverage(
    int owner,
    String unit,
    int? before,
    Map<String, dynamic> coverage,
  ) => _database.writeSettingValue(
    id: _historyKey(owner, unit, before),
    group: 'message-history',
    value: jsonEncode(coverage),
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

  Future<List<ChatMessage>> readNewerPage({
    required int ownerId,
    required String sessionUnitId,
    required int afterScore,
    int limit = 30,
  }) async => (await _database.readNewerMessageRows(
    ownerId: ownerId,
    sessionUnitId: sessionUnitId,
    afterScore: afterScore,
    limit: limit,
  )).map(ChatMessage.fromDatabaseRow).toList(growable: false);

  Future<Map<String, dynamic>> readAroundAnchorSlice({
    required int ownerId,
    required String sessionUnitId,
    required int targetServerId,
    int beforeCount = 20,
    int afterCount = 20,
  }) async {
    final raw = await _database.readAroundAnchorMessageRows(
      ownerId: ownerId,
      sessionUnitId: sessionUnitId,
      targetServerId: targetServerId,
      beforeCount: beforeCount,
      afterCount: afterCount,
    );
    final anchorRow = raw['anchor'] as Map<String, Object?>?;
    final beforeRows = raw['before'] as List<Map<String, Object?>>? ?? const [];
    final afterRows = raw['after'] as List<Map<String, Object?>>? ?? const [];

    return {
      'anchor': anchorRow == null ? null : ChatMessage.fromDatabaseRow(anchorRow),
      'before': beforeRows.map(ChatMessage.fromDatabaseRow).toList(growable: false),
      'after': afterRows.map(ChatMessage.fromDatabaseRow).toList(growable: false),
    };
  }

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

  Future<ChatMessage?> findAnyByServerId(int serverId) async {
    final row = await _database.readMessageRowAnyByServerId(serverId);
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
