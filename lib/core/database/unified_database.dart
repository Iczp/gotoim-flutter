import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';

/// Cross-platform application database.
///
/// Every supported platform uses SQLite SQL and this migration set. On native
/// platforms Drift stores `gotoim.sqlite` in the application documents folder;
/// on Web it runs the same SQLite engine through WASM and persists it using the
/// browser storage selected by Drift (OPFS when available, IndexedDB fallback).
/// Business features should depend on this class or feature repositories built
/// on it, never on platform-specific SQLite or IndexedDB APIs.
class UnifiedDatabase {
  UnifiedDatabase(this._connection);

  factory UnifiedDatabase.openDefault() => UnifiedDatabase(
    driftDatabase(
      name: databaseName,
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
    ),
  );

  static const databaseName = 'gotoim';
  static const schemaVersion = 1;
  static const diagnosticsTable = 'diagnostic_records';
  static const diagnosticsScratchTable = 'diagnostic_scratch';

  static const _baseTables = <String>{
    'Settings',
    'LoginUsers',
    'Owners',
    'ChatObjects',
    'Friends',
    'Members',
    'Messages',
    diagnosticsTable,
  };

  final DatabaseConnection _connection;
  Future<void>? _initialization;
  String? _initializationError;

  String? get initializationError => _initializationError;
  bool get isInitialized =>
      _initializationError == null && _initialization != null;

  String get storageDescription =>
      kIsWeb
          ? 'SQLite WASM（浏览器 OPFS / IndexedDB 持久化）'
          : 'SQLite 文件（应用 Documents 目录）';

  /// Runs idempotent schema creation on first open, and keeps a SQLite
  /// [schemaVersion] for later additive migrations.
  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    try {
      await _connection.ensureOpen(_UnifiedDatabaseUser());
      await _connection.runCustom('PRAGMA foreign_keys = ON');
      for (final statement in _version1Schema) {
        await _connection.runCustom(statement);
      }
      final rows = await _connection.runSelect('PRAGMA user_version', const []);
      final current = (rows.single['user_version'] as num?)?.toInt() ?? 0;
      if (current < schemaVersion) {
        await _connection.runCustom('PRAGMA user_version = $schemaVersion');
      }
    } catch (error) {
      _initializationError = error.toString();
      debugPrint('UnifiedDatabase initialization error: $error');
      rethrow;
    }
  }

  /// Shows managed and runtime-created tables, including their row counts and
  /// DDL. This powers the diagnostics page and is useful for support exports.
  Future<DatabaseOverview> inspect() async {
    await initialize();
    final tables = await _connection.runSelect(
      "SELECT name, sql FROM sqlite_master "
      "WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
      const [],
    );
    final details = <DatabaseTableInfo>[];
    for (final table in tables) {
      final name = table['name'] as String;
      final count = await _rowCount(name);
      details.add(
        DatabaseTableInfo(
          name: name,
          rowCount: count,
          createSql: table['sql'] as String? ?? '',
        ),
      );
    }
    return DatabaseOverview(
      name: databaseName,
      schemaVersion: schemaVersion,
      storage: storageDescription,
      tables: details,
    );
  }

  /// Inserts a diagnostics record. It is deliberately a normal table in the
  /// shared schema, so this CRUD test exercises the production database path.
  Future<void> insertDiagnosticRecord({
    required String id,
    required String title,
    required Map<String, Object?> payload,
  }) async {
    await initialize();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _connection.runInsert(
      'INSERT INTO $diagnosticsTable '
      '(id, title, payload, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
      <Object?>[id, title, jsonEncode(payload), now, now],
    );
  }

  Future<int> updateDiagnosticRecord({
    required String id,
    required String title,
    required Map<String, Object?> payload,
  }) async {
    await initialize();
    return _connection.runUpdate(
      'UPDATE $diagnosticsTable SET title = ?, payload = ?, updated_at = ? '
      'WHERE id = ?',
      <Object?>[
        title,
        jsonEncode(payload),
        DateTime.now().millisecondsSinceEpoch,
        id,
      ],
    );
  }

  Future<List<DatabaseDiagnosticRecord>> readDiagnosticRecords({
    int limit = 50,
  }) async {
    await initialize();
    final normalizedLimit = limit.clamp(1, 200);
    final rows = await _connection.runSelect(
      'SELECT id, title, payload, created_at, updated_at FROM $diagnosticsTable '
      'ORDER BY updated_at DESC LIMIT ?',
      <Object?>[normalizedLimit],
    );
    return rows.map(DatabaseDiagnosticRecord.fromRow).toList(growable: false);
  }

  Future<int> deleteDiagnosticRecord(String id) async {
    await initialize();
    return _connection.runDelete(
      'DELETE FROM $diagnosticsTable WHERE id = ?',
      <Object?>[id],
    );
  }

  /// Reads the locally persisted conversation summaries in display order.
  /// Feature code reaches this table through SessionDao rather than calling
  /// this database primitive directly.
  Future<List<Map<String, Object?>>> readFriendRows({
    required int ownerId,
    int? cursorScore,
    String? cursorId,
    int limit = 50,
  }) async {
    await initialize();
    final normalizedLimit = limit.clamp(1, 200);
    final hasCursor = cursorScore != null && cursorId != null;
    return _connection.runSelect(
      'SELECT id, ownerId, score, sorting, ticks, raw FROM Friends '
      'WHERE ownerId = ? '
      '${hasCursor ? 'AND (score < ? OR (score = ? AND id < ?)) ' : ''}'
      'ORDER BY score DESC, id DESC LIMIT ?',
      <Object?>[
        ownerId,
        if (hasCursor) cursorScore,
        if (hasCursor) cursorScore,
        if (hasCursor) cursorId,
        normalizedLimit,
      ],
    );
  }

  /// Repairs cache rows written by older clients which mistakenly stored a
  /// message score in Friends.score. FriendScore is defined by the backend as
  /// Sorting * 1e13 + Ticks, so this can be recovered from persisted fields
  /// without waiting for another network sync.
  Future<int> repairFriendScores(int ownerId) async {
    await initialize();
    final rows = await _connection.runSelect(
      'SELECT id, score, sorting, ticks, raw FROM Friends WHERE ownerId = ?',
      <Object?>[ownerId],
    );
    var repaired = 0;
    for (final row in rows) {
      final sorting = (row['sorting'] as num?)?.toInt() ?? 0;
      final ticks = (row['ticks'] as num?)?.toInt() ?? 0;
      final expectedScore = sorting * 10000000000000 + ticks;
      final actualScore = (row['score'] as num?)?.toInt();
      if (actualScore == expectedScore) continue;

      String? updatedRaw;
      if (row['raw'] case final String rawJson) {
        try {
          final decoded = jsonDecode(rawJson);
          if (decoded is Map) {
            final raw = Map<String, dynamic>.from(decoded);
            raw['sorting'] = sorting;
            raw['ticks'] = ticks;
            raw['score'] = expectedScore;
            updatedRaw = jsonEncode(raw);
          }
        } on FormatException {
          // Keep the cache record readable even if its raw payload is stale.
        }
      }
      await _connection.runUpdate(
        'UPDATE Friends SET score = ?, raw = COALESCE(?, raw) WHERE id = ? '
        'AND ownerId = ?',
        <Object?>[expectedScore, updatedRaw, row['id'], ownerId],
      );
      repaired++;
    }
    return repaired;
  }

  Future<List<Map<String, Object?>>> readMemberRows({
    required int ownerId,
    required String sessionUnitId,
    int? cursorScore,
    String? cursorId,
    int limit = 50,
    String keyword = '',
  }) async {
    await initialize();
    final hasCursor = cursorScore != null && cursorId != null;
    final normalizedKeyword = keyword.trim();
    return _connection.runSelect(
      'SELECT * FROM Members WHERE ownerId = ? AND sessionUnitId = ? AND isList = 1 '
      '${normalizedKeyword.isEmpty ? '' : 'AND (memberName LIKE ? OR raw LIKE ?) '}'
      '${hasCursor ? 'AND (score < ? OR (score = ? AND id < ?)) ' : ''}'
      'ORDER BY score DESC, id DESC LIMIT ?',
      <Object?>[
        ownerId,
        sessionUnitId,
        if (normalizedKeyword.isNotEmpty) '%$normalizedKeyword%',
        if (normalizedKeyword.isNotEmpty) '%$normalizedKeyword%',
        if (hasCursor) cursorScore,
        if (hasCursor) cursorScore,
        if (hasCursor) cursorId,
        limit.clamp(1, 200),
      ],
    );
  }

  Future<void> upsertMemberRows(List<Map<String, Object?>> rows) async {
    await initialize();
    for (final row in rows) {
      await _connection.runInsert(
        '''INSERT INTO Members
        (id, ownerId, sessionUnitId, memberName, isFriendship, isCreator,
         isList, score, sorting, ticks, joinTime, createTime, updateTime, raw)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET ownerId=excluded.ownerId,
        sessionUnitId=excluded.sessionUnitId, memberName=excluded.memberName,
        isFriendship=excluded.isFriendship, isCreator=excluded.isCreator,
        isList=excluded.isList, score=excluded.score, sorting=excluded.sorting,
        ticks=excluded.ticks, joinTime=excluded.joinTime,
        updateTime=excluded.updateTime, raw=excluded.raw''',
        <Object?>[
          row['id'],
          row['ownerId'],
          row['sessionUnitId'],
          row['memberName'],
          row['isFriendship'],
          row['isCreator'],
          row['isList'],
          row['score'],
          row['sorting'],
          row['ticks'],
          row['joinTime'],
          row['createTime'],
          row['updateTime'],
          row['raw'],
        ],
      );
    }
  }

  Future<void> updateFriendMemberState({
    required String sessionUnitId,
    int? memberCount,
    bool? loadedAll,
  }) async {
    await initialize();
    await _connection.runUpdate(
      'UPDATE Friends SET '
      'memberCount = COALESCE(?, memberCount), '
      'isMemberInit = 1, '
      'isMemberLoadedAll = COALESCE(?, isMemberLoadedAll), '
      'memberLoadedTime = ? WHERE id = ?',
      <Object?>[
        memberCount,
        loadedAll == null ? null : (loadedAll ? 1 : 0),
        DateTime.now().millisecondsSinceEpoch,
        sessionUnitId,
      ],
    );
  }

  Future<int> resetFriendMessages(int ownerId, String sessionUnitId) async {
    await initialize();
    final deleted = await _connection.runDelete(
      'DELETE FROM Messages WHERE ownerId = ? AND sessionUnitId = ?',
      <Object?>[ownerId, sessionUnitId],
    );
    final rows = await _connection.runSelect(
      'SELECT raw FROM Friends WHERE id = ? LIMIT 1',
      <Object?>[sessionUnitId],
    );
    String? updatedRaw;
    if (rows.isNotEmpty && rows.single['raw'] is String) {
      final raw = jsonDecode(rows.single['raw'] as String);
      if (raw is Map) {
        final friend = Map<String, dynamic>.from(raw);
        friend['lastMessage'] = null;
        friend['lastMessageId'] = null;
        friend['lastMessageTime'] = null;
        friend['publicBadge'] = 0;
        friend['privateBadge'] = 0;
        friend['badge'] = 0;
        updatedRaw = jsonEncode(friend);
      }
    }
    await _connection.runUpdate(
      'UPDATE Friends SET isMessageInit = 0, isMessageLoadedAll = 0, '
      'messageLoadedTime = NULL, updateTime = ?, raw = COALESCE(?, raw) '
      'WHERE id = ?',
      <Object?>[
        DateTime.now().millisecondsSinceEpoch,
        updatedRaw,
        sessionUnitId,
      ],
    );
    return deleted;
  }

  Future<void> updateFriendLastMessage({
    required int ownerId,
    required String sessionUnitId,
    required Map<String, dynamic> message,
    bool incrementUnreadBadge = false,
  }) async {
    await initialize();
    final rows = await _connection.runSelect(
      'SELECT raw, sorting FROM Friends WHERE id = ? AND ownerId = ? LIMIT 1',
      <Object?>[sessionUnitId, ownerId],
    );
    if (rows.isEmpty || rows.single['raw'] is! String) return;
    final decoded = jsonDecode(rows.single['raw'] as String);
    if (decoded is! Map) return;
    final raw = Map<String, dynamic>.from(decoded);
    final messageTime =
        DateTime.tryParse('${message['creationTime'] ?? ''}') ?? DateTime.now();
    final ticks = messageTime.millisecondsSinceEpoch;
    final rawSorting =
        raw['sorting'] ?? raw['Sorting'] ?? rows.single['sorting'];
    final sorting =
        rawSorting is num
            ? rawSorting.toInt()
            : int.tryParse('$rawSorting') ?? 0;
    // Friends.score is a FriendScore, not a message score.  A message score
    // (serverMessageId * 1e6) corrupts global session ordering when stored in
    // this column. Keep the backend's contract here for locally-arriving
    // messages: Sorting * 1e13 + Ticks.
    final friendScore = sorting * 10000000000000 + ticks;
    raw['lastMessage'] = message;
    raw['lastMessageTime'] = messageTime.toIso8601String();
    raw['ticks'] = ticks;
    raw['sorting'] = sorting;
    raw['score'] = friendScore;
    if (incrementUnreadBadge) {
      final current = raw['publicBadge'];
      final currentBadge =
          current is num ? current.toInt() : int.tryParse('$current') ?? 0;
      raw['publicBadge'] = currentBadge + 1;
    }
    await _connection.runUpdate(
      'UPDATE Friends SET score = ?, ticks = ?, updateTime = ?, raw = ? '
      'WHERE id = ? AND ownerId = ?',
      <Object?>[
        friendScore,
        ticks,
        ticks,
        jsonEncode(raw),
        sessionUnitId,
        ownerId,
      ],
    );
  }

  Future<Map<String, Object?>?> readFriendRow(String id) async {
    await initialize();
    final rows = await _connection.runSelect(
      'SELECT id, ownerId, score, sorting, ticks, raw FROM Friends WHERE id = ? LIMIT 1',
      <Object?>[id],
    );
    return rows.isEmpty ? null : rows.single;
  }

  Future<bool> readFriendMessagesLoadedAll(String id) async {
    await initialize();
    final rows = await _connection.runSelect(
      'SELECT isMessageLoadedAll FROM Friends WHERE id = ? LIMIT 1',
      <Object?>[id],
    );
    return rows.isNotEmpty &&
        ((rows.single['isMessageLoadedAll'] as num?)?.toInt() ?? 0) > 0;
  }

  Future<bool> readFriendMembersLoadedAll(String id) async {
    await initialize();
    final rows = await _connection.runSelect(
      'SELECT isMemberLoadedAll FROM Friends WHERE id = ? LIMIT 1',
      <Object?>[id],
    );
    return rows.isNotEmpty &&
        ((rows.single['isMemberLoadedAll'] as num?)?.toInt() ?? 0) > 0;
  }

  Future<void> writeFriendMessagesLoadedAll(String id, bool value) async {
    await initialize();
    await _connection.runUpdate(
      'UPDATE Friends SET isMessageLoadedAll = ?, updateTime = ? WHERE id = ?',
      <Object?>[value ? 1 : 0, DateTime.now().millisecondsSinceEpoch, id],
    );
  }

  Future<int?> readMaxFriendTicks(int ownerId) async {
    await initialize();
    final rows = await _connection.runSelect(
      'SELECT MAX(ticks) AS maxTicks FROM Friends WHERE ownerId = ?',
      <Object?>[ownerId],
    );
    return (rows.single['maxTicks'] as num?)?.toInt();
  }

  Future<int> countFriendRows(int ownerId) async {
    await initialize();
    final rows = await _connection.runSelect(
      'SELECT COUNT(*) AS count FROM Friends WHERE ownerId = ?',
      <Object?>[ownerId],
    );
    return (rows.single['count'] as num?)?.toInt() ?? 0;
  }

  Future<List<Map<String, Object?>>> readOwnerRows() async {
    await initialize();
    return _connection.runSelect(
      'SELECT id, name, objectType, raw FROM Owners ORDER BY id',
      const [],
    );
  }

  Future<void> upsertOwnerRows(List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return;
    await initialize();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final row in rows) {
      await _connection.runInsert(
        'INSERT INTO Owners (id, name, objectType, updateTime, raw) '
        'VALUES (?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET '
        'name = excluded.name, objectType = excluded.objectType, '
        'updateTime = excluded.updateTime, raw = excluded.raw',
        <Object?>[row['id'], row['name'], row['objectType'], now, row['raw']],
      );
    }
  }

  Future<String?> readSettingValue(String id) async {
    await initialize();
    final rows = await _connection.runSelect(
      'SELECT value FROM Settings WHERE id = ? LIMIT 1',
      <Object?>[id],
    );
    return rows.isEmpty ? null : rows.single['value'] as String?;
  }

  Future<void> writeSettingValue({
    required String id,
    required String group,
    required String value,
  }) async {
    await initialize();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _connection.runInsert(
      'INSERT INTO Settings (id, [group], type, value, createTime, updateTime) '
      "VALUES (?, ?, 'string', ?, ?, ?) ON CONFLICT(id) DO UPDATE SET "
      'value = excluded.value, updateTime = excluded.updateTime',
      <Object?>[id, group, value, now, now],
    );
  }

  /// Persists remote session-unit summaries without deleting local records
  /// that are outside the current server page.
  Future<void> upsertFriendRows(List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return;
    await initialize();
    for (final row in rows) {
      await _connection.runInsert(
        'INSERT INTO Friends '
        '(id, ownerId, score, sorting, ticks, createTime, updateTime, '
        'expireTime, raw) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) '
        'ON CONFLICT(id) DO UPDATE SET '
        'ownerId = excluded.ownerId, score = excluded.score, '
        'sorting = excluded.sorting, ticks = excluded.ticks, '
        'createTime = excluded.createTime, updateTime = excluded.updateTime, '
        'expireTime = excluded.expireTime, raw = excluded.raw',
        <Object?>[
          row['id'],
          row['ownerId'],
          row['score'],
          row['sorting'],
          row['ticks'],
          row['createTime'],
          row['updateTime'],
          row['expireTime'],
          row['raw'],
        ],
      );
    }
  }

  Future<List<Map<String, Object?>>> readMessageRows({
    required int ownerId,
    required String sessionUnitId,
    int? beforeScore,
    int limit = 30,
  }) async {
    await initialize();
    return _connection.runSelect(
      'SELECT * FROM Messages WHERE ownerId = ? AND sessionUnitId = ? '
      '${beforeScore == null ? '' : 'AND score < ? '}'
      'ORDER BY score DESC LIMIT ?',
      <Object?>[
        ownerId,
        sessionUnitId,
        if (beforeScore != null) beforeScore,
        limit.clamp(1, 100),
      ],
    );
  }

  Future<int> countMessageRows(int ownerId, String sessionUnitId) async {
    await initialize();
    final rows = await _connection.runSelect(
      'SELECT COUNT(*) AS count FROM Messages WHERE ownerId = ? AND sessionUnitId = ?',
      <Object?>[ownerId, sessionUnitId],
    );
    return (rows.single['count'] as num?)?.toInt() ?? 0;
  }

  Future<Map<String, Object?>?> readMessageRowByServerId({
    required int ownerId,
    required String sessionUnitId,
    required int serverId,
  }) async {
    await initialize();
    final rows = await _connection.runSelect(
      'SELECT * FROM Messages WHERE ownerId = ? AND sessionUnitId = ? '
      'AND serverId = ? LIMIT 1',
      <Object?>[ownerId, sessionUnitId, serverId],
    );
    return rows.isEmpty ? null : rows.single;
  }

  Future<int> readMaxMessageScore(int ownerId, String sessionUnitId) async {
    await initialize();
    final rows = await _connection.runSelect(
      'SELECT MAX(score) AS score FROM Messages WHERE ownerId = ? AND sessionUnitId = ?',
      <Object?>[ownerId, sessionUnitId],
    );
    return (rows.single['score'] as num?)?.toInt() ?? 0;
  }

  Future<int> readMaxMessageServerId(int ownerId, String sessionUnitId) async {
    await initialize();
    final rows = await _connection.runSelect(
      'SELECT MAX(serverId) AS serverId FROM Messages '
      'WHERE ownerId = ? AND sessionUnitId = ?',
      <Object?>[ownerId, sessionUnitId],
    );
    return (rows.single['serverId'] as num?)?.toInt() ?? 0;
  }

  Future<void> markMessageOpened(String localId) async {
    await initialize();
    final rows = await _connection.runSelect(
      'SELECT raw FROM Messages WHERE id = ? LIMIT 1',
      <Object?>[localId],
    );
    if (rows.isEmpty || rows.single['raw'] is! String) return;
    final decoded = jsonDecode(rows.single['raw'] as String);
    if (decoded is! Map) return;
    final raw = Map<String, dynamic>.from(decoded)..['isOpened'] = true;
    await _connection.runUpdate(
      'UPDATE Messages SET raw = ? WHERE id = ?',
      <Object?>[jsonEncode(raw), localId],
    );
  }

  Future<void> deleteMessageRows(Iterable<String> localIds) async {
    await initialize();
    for (final localId in localIds) {
      await _connection.runDelete(
        'DELETE FROM Messages WHERE id = ?',
        <Object?>[localId],
      );
    }
  }

  Future<void> upsertMessageRows(List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return;
    await initialize();
    for (final row in rows) {
      await _connection.runInsert(
        'INSERT INTO Messages (id, serverId, score, clientMessageId, ownerId, '
        'sessionUnitId, senderSessionUnitId, messageType, state, createTime, raw) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET '
        'serverId = COALESCE(excluded.serverId, Messages.serverId), '
        'score = excluded.score, '
        'clientMessageId = COALESCE(excluded.clientMessageId, Messages.clientMessageId), '
        'ownerId = excluded.ownerId, '
        'sessionUnitId = excluded.sessionUnitId, '
        'state = excluded.state, '
        'raw = excluded.raw, '
        'updateTime = excluded.createTime',
        <Object?>[
          row['id'],
          row['serverId'],
          row['score'],
          row['clientMessageId'],
          row['ownerId'],
          row['sessionUnitId'],
          row['senderSessionUnitId'],
          row['messageType'],
          row['state'],
          row['createTime'],
          row['raw'],
        ],
      );
    }
  }

  /// Searches local friends / sessions matching [keyword] for the given [ownerId].
  Future<List<Map<String, Object?>>> searchFriendRows({
    required int ownerId,
    required String keyword,
    int limit = 30,
  }) async {
    await initialize();
    final term = keyword.trim();
    if (term.isEmpty) return const <Map<String, Object?>>[];
    if (ownerId > 0) {
      return _connection.runSelect(
        'SELECT * FROM Friends WHERE ownerId = ? AND raw LIKE ? ORDER BY score DESC, id DESC LIMIT ?',
        <Object?>[ownerId, '%$term%', limit],
      );
    }
    return _connection.runSelect(
      'SELECT * FROM Friends WHERE raw LIKE ? ORDER BY score DESC, id DESC LIMIT ?',
      <Object?>['%$term%', limit],
    );
  }

  /// Searches local messages containing [keyword] for the given [ownerId].
  Future<List<Map<String, Object?>>> searchMessageRows({
    required int ownerId,
    required String keyword,
    int limit = 50,
  }) async {
    await initialize();
    final term = keyword.trim();
    if (term.isEmpty) return const <Map<String, Object?>>[];
    if (ownerId > 0) {
      return _connection.runSelect(
        'SELECT * FROM Messages WHERE ownerId = ? AND raw LIKE ? ORDER BY score DESC LIMIT ?',
        <Object?>[ownerId, '%$term%', limit],
      );
    }
    return _connection.runSelect(
      'SELECT * FROM Messages WHERE raw LIKE ? ORDER BY score DESC LIMIT ?',
      <Object?>['%$term%', limit],
    );
  }

  /// Reads persistent search keyword history from the Settings table.
  Future<List<String>> readSearchHistory() async {
    final raw = await readSettingValue('search_history_keywords');
    if (raw == null || raw.trim().isEmpty) return const <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return const <String>[];
  }

  /// Adds a keyword to persistent search history, prepending and deduplicating.
  Future<List<String>> addSearchKeyword(
    String keyword, {
    int maxCount = 20,
  }) async {
    final term = keyword.trim();
    if (term.isEmpty) return readSearchHistory();
    final current = await readSearchHistory();
    final updated = <String>[term, ...current.where((e) => e != term)];
    final truncated = updated.take(maxCount).toList(growable: false);
    await writeSettingValue(
      id: 'search_history_keywords',
      group: 'search',
      value: jsonEncode(truncated),
    );
    return truncated;
  }

  /// Deletes a specific keyword from persistent search history.
  Future<List<String>> deleteSearchKeyword(String keyword) async {
    final term = keyword.trim();
    final current = await readSearchHistory();
    final updated = current.where((e) => e != term).toList(growable: false);
    await writeSettingValue(
      id: 'search_history_keywords',
      group: 'search',
      value: jsonEncode(updated),
    );
    return updated;
  }

  /// Clears all search history keywords.
  Future<void> clearSearchHistory() async {
    await writeSettingValue(
      id: 'search_history_keywords',
      group: 'search',
      value: '[]',
    );
  }

  /// Empties a known schema table. Arbitrary SQL/table names are intentionally
  /// not accepted by this application-level API.
  Future<int> clearTable(String table) async {
    await initialize();
    _assertManagedTable(table);
    return _connection.runDelete('DELETE FROM ${_quote(table)}', const []);
  }

  /// A deliberately temporary table used to verify CREATE TABLE support in
  /// the diagnostics centre. It is not part of the application schema.
  Future<void> createDiagnosticsScratchTable() async {
    await initialize();
    await _connection.runCustom(
      'CREATE TABLE IF NOT EXISTS $diagnosticsScratchTable ('
      'id TEXT PRIMARY KEY, note TEXT NOT NULL, created_at INTEGER NOT NULL)',
    );
  }

  Future<void> dropDiagnosticsScratchTable() async {
    await initialize();
    await _connection.runCustom(
      'DROP TABLE IF EXISTS $diagnosticsScratchTable',
    );
  }

  // ── 诊断专用：消息查询（不强制 ownerId）────────────────────────────────────

  /// 按 [sessionUnitId] 统计本地消息，按 ownerId 分组。
  /// 诊断用途：不需要提前知道 ownerId。
  Future<List<Map<String, Object?>>> queryMessageStatsBySession(
    String sessionUnitId,
  ) async {
    await initialize();
    return _connection.runSelect(
      'SELECT ownerId, COUNT(*) AS count, '
      'MAX(serverId) AS maxServerId, MAX(score) AS maxScore, '
      'MIN(score) AS minScore '
      'FROM Messages WHERE sessionUnitId = ? GROUP BY ownerId',
      <Object?>[sessionUnitId],
    );
  }

  /// 按 [sessionUnitId] 返回最新 [limit] 条消息（不过滤 ownerId），raw 字段截断至 300 字符。
  /// 诊断用途：不需要提前知道 ownerId。
  Future<List<Map<String, Object?>>> queryMessagesBySession(
    String sessionUnitId, {
    int limit = 10,
  }) async {
    await initialize();
    final rows = await _connection.runSelect(
      'SELECT id, ownerId, sessionUnitId, serverId, score, '
      'substr(raw, 1, 300) AS raw_preview '
      'FROM Messages WHERE sessionUnitId = ? '
      'ORDER BY score DESC LIMIT ?',
      <Object?>[sessionUnitId, limit.clamp(1, 100)],
    );
    return rows;
  }

  Future<void> close() => _connection.close();

  Future<int> _rowCount(String table) async {
    final rows = await _connection.runSelect(
      'SELECT COUNT(*) AS count FROM ${_quote(table)}',
      const [],
    );
    return (rows.single['count'] as num?)?.toInt() ?? 0;
  }

  void _assertManagedTable(String table) {
    if (!_baseTables.contains(table) && table != diagnosticsScratchTable) {
      throw ArgumentError.value(table, 'table', '不是受 UnifiedDatabase 管理的表');
    }
  }

  String _quote(String identifier) {
    final escaped = identifier.replaceAll('"', '""');
    return '"$escaped"';
  }
}

class DatabaseOverview {
  const DatabaseOverview({
    required this.name,
    required this.schemaVersion,
    required this.storage,
    required this.tables,
  });

  final String name;
  final int schemaVersion;
  final String storage;
  final List<DatabaseTableInfo> tables;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'schemaVersion': schemaVersion,
    'storage': storage,
    'tables': tables.map((table) => table.toJson()).toList(),
  };
}

class DatabaseTableInfo {
  const DatabaseTableInfo({
    required this.name,
    required this.rowCount,
    required this.createSql,
  });

  final String name;
  final int rowCount;
  final String createSql;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'rowCount': rowCount,
    'createSql': createSql,
  };
}

class DatabaseDiagnosticRecord {
  const DatabaseDiagnosticRecord({
    required this.id,
    required this.title,
    required this.payload,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DatabaseDiagnosticRecord.fromRow(Map<String, Object?> row) {
    final rawPayload = row['payload'] as String;
    return DatabaseDiagnosticRecord(
      id: row['id'] as String,
      title: row['title'] as String,
      payload: (jsonDecode(rawPayload) as Map).cast<String, Object?>(),
      createdAt: (row['created_at'] as num).toInt(),
      updatedAt: (row['updated_at'] as num).toInt(),
    );
  }

  final String id;
  final String title;
  final Map<String, Object?> payload;
  final int createdAt;
  final int updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'payload': payload,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };
}

const _version1Schema = <String>[
  '''CREATE TABLE IF NOT EXISTS Settings (
    id TEXT PRIMARY KEY, [group] TEXT, type TEXT, value TEXT,
    createTime INTEGER, updateTime INTEGER, expireTime INTEGER, raw TEXT
  )''',
  'CREATE INDEX IF NOT EXISTS idx_settings_group ON Settings ([group])',
  '''CREATE TABLE IF NOT EXISTS LoginUsers (
    id TEXT PRIMARY KEY, name TEXT, account TEXT, password TEXT, avatar TEXT,
    token TEXT, email TEXT, email_verified INTEGER, phone_number TEXT,
    phone_number_verified INTEGER, is_current INTEGER, loginTime INTEGER,
    logoutTime INTEGER, createTime INTEGER, updateTime INTEGER, expireTime INTEGER,
    raw TEXT
  )''',
  'CREATE INDEX IF NOT EXISTS idx_login_users_current ON LoginUsers (is_current)',
  '''CREATE TABLE IF NOT EXISTS ChatObjects (
    id INTEGER PRIMARY KEY, name TEXT, objectType TEXT, createTime INTEGER,
    updateTime INTEGER, expireTime INTEGER, raw TEXT
  )''',
  'CREATE INDEX IF NOT EXISTS idx_chat_objects_name ON ChatObjects (name)',
  '''CREATE TABLE IF NOT EXISTS Owners (
    id INTEGER PRIMARY KEY, name TEXT, objectType TEXT, appUserId TEXT,
    createTime INTEGER, updateTime INTEGER, expireTime INTEGER, raw TEXT
  )''',
  'CREATE INDEX IF NOT EXISTS idx_owners_name ON Owners (name)',
  '''CREATE TABLE IF NOT EXISTS Friends (
    id TEXT PRIMARY KEY, ownerId INTEGER, isMemberInit INTEGER,
    isMemberLoadedAll INTEGER, isMessageInit INTEGER, isMessageLoadedAll INTEGER,
    memberLoadedTime INTEGER, messageLoadedTime INTEGER, memberCount INTEGER,
    score INTEGER, sorting INTEGER, ticks INTEGER, createTime INTEGER,
    updateTime INTEGER, expireTime INTEGER, raw TEXT
  )''',
  'CREATE INDEX IF NOT EXISTS idx_friends_cursor ON Friends (ownerId, score DESC, id DESC)',
  'CREATE INDEX IF NOT EXISTS idx_friends_owner_ticks ON Friends (ownerId, ticks DESC)',
  '''CREATE TABLE IF NOT EXISTS Members (
    id TEXT PRIMARY KEY, ownerId INTEGER, sessionUnitId TEXT, memberName TEXT,
    isFriendship INTEGER, isCreator INTEGER, isList INTEGER, score INTEGER,
    sorting INTEGER, ticks INTEGER, joinTime INTEGER, createTime INTEGER,
    updateTime INTEGER, expireTime INTEGER, raw TEXT
  )''',
  'CREATE INDEX IF NOT EXISTS idx_members_cursor ON Members (ownerId, sessionUnitId, isList, score DESC, id DESC)',
  'CREATE INDEX IF NOT EXISTS idx_members_creator_join_time ON Members (ownerId, sessionUnitId, isCreator DESC, joinTime ASC, id DESC)',
  '''CREATE TABLE IF NOT EXISTS Messages (
    id TEXT PRIMARY KEY, serverId INTEGER, score INTEGER NOT NULL,
    clientMessageId TEXT, sessionId TEXT, ownerId INTEGER, sessionUnitId TEXT,
    senderId INTEGER, senderSessionUnitId TEXT, messageType INTEGER, state TEXT,
    quoteMessageId INTEGER, renderHeight INTEGER, createTime INTEGER,
    updateTime INTEGER, expireTime INTEGER, raw TEXT
  )''',
  'CREATE INDEX IF NOT EXISTS idx_messages_client_id ON Messages (clientMessageId)',
  'CREATE INDEX IF NOT EXISTS idx_messages_server_id ON Messages (serverId)',
  'CREATE INDEX IF NOT EXISTS idx_messages_cursor ON Messages (ownerId, sessionUnitId, score DESC)',
  'CREATE INDEX IF NOT EXISTS idx_messages_cursor_server_id ON Messages (ownerId, sessionUnitId, serverId)',
  '''CREATE TABLE IF NOT EXISTS diagnostic_records (
    id TEXT PRIMARY KEY, title TEXT NOT NULL, payload TEXT NOT NULL,
    created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
  )''',
  'CREATE INDEX IF NOT EXISTS idx_diagnostic_records_updated_at ON diagnostic_records (updated_at DESC)',
];

class _UnifiedDatabaseUser extends QueryExecutorUser {
  @override
  int get schemaVersion => UnifiedDatabase.schemaVersion;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}
