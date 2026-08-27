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
      'SELECT id, ownerId, score, ticks, raw FROM Friends '
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
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_client_id ON Messages (clientMessageId)',
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
