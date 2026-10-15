part of 'unified_database.dart';

extension MessageSyncDatabase on UnifiedDatabase {
  Future<void> _protectSyncedFriendSummaries(
    List<Map<String, Object?>> rows,
  ) async {
    for (var offset = 0; offset < rows.length; offset += 200) {
      final ids = rows.skip(offset).take(200).map((row) => row['id']).toList();
      const match =
          "s.ownerId = Friends.ownerId AND s.sessionUnitId = Friends.id AND s.messageId = CAST(json_extract(Friends.raw, '\$.lastMessage.id') AS INTEGER)";
      await _connection.runUpdate(
        "UPDATE Friends SET raw = json_set(raw, '\$.lastMessage.isRollbacked', json('true'), '\$.lastMessage.rollbackTime', "
        "(SELECT rollbackTime FROM MessageLocalStates s WHERE $match ORDER BY version DESC LIMIT 1)) "
        'WHERE id IN (${List.filled(ids.length, '?').join(',')}) AND EXISTS (SELECT 1 FROM MessageLocalStates s WHERE $match AND s.isDeleted = 0)',
        ids,
      );
      await _connection.runUpdate(
        "UPDATE Friends SET raw = json_set(raw, '\$.lastMessage', json((SELECT raw FROM Messages m "
        "WHERE m.ownerId = Friends.ownerId AND m.sessionUnitId = Friends.id AND m.serverId IS NOT NULL ORDER BY m.score DESC LIMIT 1))) "
        'WHERE id IN (${List.filled(ids.length, '?').join(',')}) AND EXISTS (SELECT 1 FROM MessageLocalStates s WHERE $match AND s.isDeleted = 1)',
        ids,
      );
    }
  }

  Future<List<Map<String, Object?>>> readMessageRowsByIds(
    int owner,
    String unit,
    List<int> ids,
  ) async {
    await initialize();
    if (ids.isEmpty) return [];
    return _connection.runSelect(
      'SELECT * FROM Messages WHERE ownerId = ? AND sessionUnitId = ? AND serverId IN (${List.filled(ids.length, '?').join(',')})',
      [owner, unit, ...ids],
    );
  }

  Future<List<Map<String, Object?>>> _mergeMessageSyncStates(
    List<Map<String, Object?>> rows,
    QueryExecutor executor,
  ) async {
    final merged = <Map<String, Object?>>[];
    for (var offset = 0; offset < rows.length; offset += 100) {
      final batch = rows.skip(offset).take(100).toList();
      final conditions = List.filled(
        batch.length,
        '(ownerId = ? AND sessionUnitId = ? AND ((serverId IS NOT NULL AND serverId = ?) OR (clientMessageId IS NOT NULL AND clientMessageId = ?)))',
      ).join(' OR ');
      final existingRows = await executor.runSelect(
        'SELECT * FROM Messages WHERE $conditions',
        [
          for (final row in batch) ...[
            row['ownerId'],
            row['sessionUnitId'],
            row['serverId'],
            row['clientMessageId'],
          ],
        ],
      );
      final byServer = {
        for (final row in existingRows)
          if (row['serverId'] != null)
            '${row['ownerId']}:${row['sessionUnitId']}:${row['serverId']}': row,
      };
      final byClient = {
        for (final row in existingRows)
          if (row['clientMessageId'] != null)
            '${row['ownerId']}:${row['sessionUnitId']}:${row['clientMessageId']}':
                row,
      };
      final tuples = <String>[];
      final args = <Object?>[];
      for (final row in batch) {
        tuples.add('(?, ?, ?, ?)');
        args.addAll([
          row['syncNamespace'] ?? '',
          row['ownerId'],
          row['sessionUnitId'],
          row['serverId'],
        ]);
        final raw = jsonDecode(row['raw'] as String) as Map;
        final quote = raw['quoteMessage'];
        if (quote is Map && quote['id'] != null) {
          tuples.add('(?, ?, ?, ?)');
          args.addAll([
            row['syncNamespace'] ?? '',
            row['ownerId'],
            row['sessionUnitId'],
            int.tryParse('${quote['id']}'),
          ]);
        }
      }
      final states = await executor.runSelect(
        'SELECT * FROM MessageLocalStates WHERE (namespace, ownerId, sessionUnitId, messageId) IN (${tuples.join(',')})',
        args,
      );
      final byKey = {
        for (final row in states)
          '${row['namespace']}:${row['ownerId']}:${row['sessionUnitId']}:${row['messageId']}':
              row,
      };
      for (final row in batch) {
        final state =
            byKey['${row['syncNamespace'] ?? ''}:${row['ownerId']}:${row['sessionUnitId']}:${row['serverId']}'];
        if (state?['isDeleted'] == 1) continue;
        final existing =
            byServer['${row['ownerId']}:${row['sessionUnitId']}:${row['serverId']}'] ??
            byClient['${row['ownerId']}:${row['sessionUnitId']}:${row['clientMessageId']}'];
        final oldRaw =
            existing == null
                ? <String, dynamic>{}
                : Map<String, dynamic>.from(
                  jsonDecode(existing['raw'] as String) as Map,
                );
        final incoming = Map<String, dynamic>.from(
          jsonDecode(row['raw'] as String) as Map,
        );
        final raw = <String, dynamic>{
          ...oldRaw,
          ...Map.fromEntries(
            incoming.entries.where((entry) => entry.value != null),
          ),
        };
        final oldSender = oldRaw['senderSessionUnit'];
        final newSender = incoming['senderSessionUnit'];
        if (oldSender is Map || newSender is Map) {
          raw['senderSessionUnit'] = {
            if (oldSender is Map) ...oldSender,
            if (newSender is Map)
              ...Map.fromEntries(
                newSender.entries.where((entry) => entry.value != null),
              ),
            if ((oldSender is Map && oldSender['owner'] is Map) ||
                (newSender is Map && newSender['owner'] is Map))
              'owner': {
                if (oldSender is Map && oldSender['owner'] is Map)
                  ...(oldSender['owner'] as Map),
                if (newSender is Map && newSender['owner'] is Map)
                  ...Map.fromEntries(
                    (newSender['owner'] as Map).entries.where(
                      (entry) => entry.value != null,
                    ),
                  ),
              },
          };
        }
        if (state != null) {
          raw['isRollbacked'] = true;
          raw['rollbackTime'] = state['rollbackTime'];
          raw['syncVersion'] = state['version'];
        }
        final quote = raw['quoteMessage'];
        if (quote is Map) {
          final quoteState =
              byKey['${row['syncNamespace'] ?? ''}:${row['ownerId']}:${row['sessionUnitId']}:${quote['id']}'];
          if (quoteState?['isDeleted'] == 1) {
            raw['quoteMessage'] = {
              ...quote,
              'isDeleted': true,
              'content': null,
            };
          } else if (quoteState != null) {
            raw['quoteMessage'] = {
              ...quote,
              'isRollbacked': true,
              'rollbackTime': quoteState['rollbackTime'],
            };
          }
        }
        merged.add({
          ...row,
          if (existing != null) 'id': existing['id'],
          'senderSessionUnitId':
              row['senderSessionUnitId'] ?? existing?['senderSessionUnitId'],
          'createTime': row['createTime'] ?? existing?['createTime'],
          'raw': jsonEncode(raw),
        });
      }
    }
    return merged;
  }

  Future<void> _repairDeletedSummary(
    QueryExecutor executor,
    int owner,
    String unit,
  ) async {
    final friends = await executor.runSelect(
      "SELECT raw FROM Friends f WHERE ownerId = ? AND id = ? AND EXISTS ("
      "SELECT 1 FROM MessageLocalStates s WHERE s.ownerId = f.ownerId AND s.sessionUnitId = f.id "
      "AND s.messageId = CAST(json_extract(f.raw, '\$.lastMessage.id') AS INTEGER) AND s.isDeleted = 1)",
      [owner, unit],
    );
    if (friends.isEmpty) return;
    final next = await executor.runSelect(
      'SELECT raw FROM Messages WHERE ownerId = ? AND sessionUnitId = ? AND serverId IS NOT NULL ORDER BY score DESC LIMIT 1',
      [owner, unit],
    );
    final raw = Map<String, dynamic>.from(
      jsonDecode(friends.single['raw'] as String) as Map,
    );
    raw['lastMessage'] =
        next.isEmpty ? null : jsonDecode(next.single['raw'] as String);
    await executor.runUpdate(
      'UPDATE Friends SET raw = ? WHERE ownerId = ? AND id = ?',
      [jsonEncode(raw), owner, unit],
    );
  }

  String _cursorKey(String namespace, int owner, String unit) =>
      'message-sync:v1:$namespace:$owner:$unit';

  Future<void> resetMessageSyncCursors(String namespace, int owner) async {
    await initialize();
    final prefix = _cursorKey(namespace, owner, '');
    await _connection.runDelete(
      "DELETE FROM Settings WHERE [group] = 'message-sync' AND substr(id, 1, ?) = ?",
      [prefix.length, prefix],
    );
  }

  Future<String?> readMessageSyncCursor(
    String namespace,
    int owner,
    String unit,
  ) => readSettingValue(_cursorKey(namespace, owner, unit));

  Future<List<String>> readMessageSyncScopes(
    int owner,
    String after,
    int limit,
  ) async {
    await initialize();
    final rows = await _connection.runSelect(
      'SELECT sessionUnitId FROM ('
      'SELECT sessionUnitId FROM Messages WHERE ownerId = ? '
      "UNION SELECT id AS sessionUnitId FROM Friends WHERE ownerId = ? AND json_extract(raw, '\$.lastMessage.id') IS NOT NULL"
      ') WHERE sessionUnitId > ? GROUP BY sessionUnitId ORDER BY sessionUnitId LIMIT ?',
      [owner, owner, after, limit],
    );
    return rows.map((row) => row['sessionUnitId'] as String).toList();
  }

  Future<List<int>> readMessageSyncIds(
    int owner,
    String unit,
    int after,
    int limit,
  ) async {
    await initialize();
    final rows = await _connection.runSelect(
      'SELECT messageId FROM ('
      'SELECT serverId AS messageId FROM Messages WHERE ownerId = ? AND sessionUnitId = ? '
      "UNION SELECT CAST(json_extract(raw, '\$.lastMessage.id') AS INTEGER) AS messageId FROM Friends WHERE ownerId = ? AND id = ? "
      "UNION SELECT CAST(json_extract(raw, '\$.quoteMessage.id') AS INTEGER) AS messageId FROM Messages WHERE ownerId = ? AND sessionUnitId = ?"
      ') WHERE messageId > ? ORDER BY messageId LIMIT ?',
      [owner, unit, owner, unit, owner, unit, after, limit],
    );
    return rows.map((row) => (row['messageId'] as num).toInt()).toList();
  }

  /// A page and its checkpoint either both commit or are both retried.
  Future<void> applyMessageSyncPage({
    required String namespace,
    required int owner,
    required String unit,
    required List<Map<String, dynamic>> items,
    String? cursor,
  }) async {
    await initialize();
    final tx = _connection.beginTransaction();
    await tx.ensureOpen(_UnifiedDatabaseUser());
    try {
      for (final item in items) {
        final id = int.tryParse('${item['messageId']}');
        final version = int.tryParse('${item['syncVersion'] ?? 0}') ?? 0;
        final isDeleted = item['isDeleted'] == true;
        if (id == null ||
            !(isDeleted ||
                item['isRollbacked'] == true ||
                item['rollbackTime'] != null)) {
          continue;
        }
        if (isDeleted) {
          await tx.runInsert(
            'INSERT INTO MessageLocalStates (namespace, ownerId, sessionUnitId, messageId, version, isDeleted) '
            'VALUES (?, ?, ?, ?, ?, 1) ON CONFLICT(namespace, ownerId, sessionUnitId, messageId) DO UPDATE SET '
            'version = MAX(MessageLocalStates.version, excluded.version), isDeleted = 1',
            [namespace, owner, unit, id, version],
          );
          await tx.runDelete(
            'DELETE FROM Messages WHERE ownerId = ? AND sessionUnitId = ? AND serverId = ?',
            [owner, unit, id],
          );
          await tx.runUpdate(
            "UPDATE Messages SET raw = json_set(raw, '\$.quoteMessage.isDeleted', json('true'), '\$.quoteMessage.content', NULL) "
            "WHERE ownerId = ? AND sessionUnitId = ? AND CAST(json_extract(raw, '\$.quoteMessage.id') AS INTEGER) = ?",
            [owner, unit, id],
          );
          continue;
        }
        final time = item['rollbackTime'] ?? item['changedAt'];
        await tx.runInsert(
          'INSERT INTO MessageLocalStates (namespace, ownerId, sessionUnitId, messageId, version, rollbackTime) '
          'VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(namespace, ownerId, sessionUnitId, messageId) DO UPDATE SET '
          'version = MAX(MessageLocalStates.version, excluded.version), '
          'rollbackTime = CASE WHEN excluded.version >= MessageLocalStates.version THEN excluded.rollbackTime ELSE MessageLocalStates.rollbackTime END',
          [namespace, owner, unit, id, version, time],
        );
        await tx.runUpdate(
          "UPDATE Messages SET raw = json_set(raw, '\$.isRollbacked', json('true'), '\$.rollbackTime', ?, '\$.syncVersion', ?) "
          "WHERE ownerId = ? AND sessionUnitId = ? AND serverId = ? AND COALESCE(CAST(json_extract(raw, '\$.syncVersion') AS INTEGER), 0) <= ?",
          [time, version, owner, unit, id, version],
        );
        await tx.runUpdate(
          "UPDATE Messages SET raw = json_set(raw, '\$.quoteMessage.isRollbacked', json('true'), '\$.quoteMessage.rollbackTime', ?) "
          "WHERE ownerId = ? AND sessionUnitId = ? AND CAST(json_extract(raw, '\$.quoteMessage.id') AS INTEGER) = ?",
          [time, owner, unit, id],
        );
        await tx.runUpdate(
          "UPDATE Friends SET raw = json_set(raw, '\$.lastMessage.isRollbacked', json('true'), '\$.lastMessage.rollbackTime', ?) "
          "WHERE ownerId = ? AND id = ? AND CAST(json_extract(raw, '\$.lastMessage.id') AS INTEGER) = ?",
          [time, owner, unit, id],
        );
      }
      await _repairDeletedSummary(tx, owner, unit);
      if (cursor != null) {
        await tx.runInsert(
          'INSERT INTO Settings (id, [group], type, value) VALUES (?, ?, ?, ?) '
          'ON CONFLICT(id) DO UPDATE SET value = excluded.value',
          [
            _cursorKey(namespace, owner, unit),
            'message-sync',
            'string',
            cursor,
          ],
        );
      }
      await tx.send();
    } catch (_) {
      await tx.rollback();
      rethrow;
    }
  }
}
