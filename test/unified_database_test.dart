import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/database/unified_database.dart';
import 'package:gotoim_flutter/features/chat/data/datasources/message_dao.dart';
import 'package:gotoim_flutter/features/chat/data/models/chat_message.dart';

void main() {
  UnifiedDatabase createDatabase() {
    final database = UnifiedDatabase(
      DatabaseConnection(NativeDatabase.memory()),
    );
    addTearDown(database.close);
    return database;
  }

  test('current schema creates the unified chat tables and indexes', () async {
    final database = createDatabase();

    final overview = await database.inspect();
    final tableNames = overview.tables.map((table) => table.name).toSet();

    expect(overview.name, UnifiedDatabase.databaseName);
    expect(overview.schemaVersion, UnifiedDatabase.schemaVersion);
    expect(
      tableNames,
      containsAll(<String>[
        'Settings',
        'LoginUsers',
        'Owners',
        'ChatObjects',
        'Friends',
        'Members',
        'Messages',
        UnifiedDatabase.diagnosticsTable,
      ]),
    );
    final owners = overview.tables.singleWhere(
      (table) => table.name == 'Owners',
    );
    final chatObjects = overview.tables.singleWhere(
      (table) => table.name == 'ChatObjects',
    );
    expect(owners.createSql, contains('CREATE TABLE'));
    expect(chatObjects.createSql, contains('CREATE TABLE'));
  });

  test('version 2 rollback markers survive the additive deletion upgrade', () async {
    final database = UnifiedDatabase(
      DatabaseConnection(
        NativeDatabase.memory(
          setup: (sqlite) {
            sqlite.execute(
              'CREATE TABLE MessageLocalStates (namespace TEXT NOT NULL, ownerId INTEGER NOT NULL, '
              'sessionUnitId TEXT NOT NULL, messageId INTEGER NOT NULL, version INTEGER NOT NULL, rollbackTime TEXT, '
              'PRIMARY KEY(namespace, ownerId, sessionUnitId, messageId))',
            );
            sqlite.execute(
              "INSERT INTO MessageLocalStates VALUES ('', 1, 'unit', 5, 7, '2026-10-14T02:00:00Z')",
            );
            sqlite.execute('PRAGMA user_version=2');
            sqlite.execute(
              'CREATE TABLE Settings (id TEXT PRIMARY KEY, [group] TEXT, type TEXT, value TEXT, createTime INTEGER, updateTime INTEGER)',
            );
            sqlite.execute(
              "INSERT INTO Settings (id, [group], value) VALUES ('message-sync:v1::1:unit', 'message-sync', 'old-cursor')",
            );
          },
        ),
      ),
    );
    addTearDown(database.close);
    final overview = await database.inspect();
    expect(overview.schemaVersion, 3);
    expect(
      overview.tables
          .singleWhere((table) => table.name == 'MessageLocalStates')
          .createSql,
      contains('isDeleted'),
    );
    // Replaying the old marker and adding a deletion use the same upgraded table.
    final dao = MessageDao(database);
    expect(await dao.syncCursor(1, 'unit'), isNull);
    await dao.upsertAll([
      ChatMessage.fromJson(
        {
          'id': 5,
          'content': {'text': 'old'},
        },
        ownerId: 1,
        sessionUnitId: 'unit',
      ),
    ]);
    expect(
      (await dao.readPage(
        ownerId: 1,
        sessionUnitId: 'unit',
      )).single.isRollbacked,
      isTrue,
    );
    await dao.applySyncPage(1, 'unit', [
      {'messageId': 6, 'syncVersion': 8, 'isDeleted': true},
    ], cursor: 'done');
    expect(await dao.syncCursor(1, 'unit'), 'done');
    expect(await dao.syncIds(1, 'unit', 0, 200), [5]);
  });

  test(
    'diagnostic records support insert select update delete and clear',
    () async {
      final database = createDatabase();

      await database.insertDiagnosticRecord(
        id: 'record-1',
        title: 'first',
        payload: <String, Object?>{'version': 1},
      );
      expect(
        (await database.readDiagnosticRecords()).single.payload,
        <String, Object?>{'version': 1},
      );

      final updated = await database.updateDiagnosticRecord(
        id: 'record-1',
        title: 'updated',
        payload: <String, Object?>{'version': 2},
      );
      expect(updated, 1);
      final record = (await database.readDiagnosticRecords()).single;
      expect(record.title, 'updated');
      expect(record.payload, <String, Object?>{'version': 2});

      expect(await database.deleteDiagnosticRecord('record-1'), 1);
      expect(await database.readDiagnosticRecords(), isEmpty);

      await database.insertDiagnosticRecord(
        id: 'record-2',
        title: 'clear me',
        payload: const <String, Object?>{},
      );
      expect(await database.clearTable(UnifiedDatabase.diagnosticsTable), 1);
      expect(await database.readDiagnosticRecords(), isEmpty);
    },
  );

  test('diagnostic scratch table can be created and dropped', () async {
    final database = createDatabase();

    await database.createDiagnosticsScratchTable();
    expect(
      (await database.inspect()).tables.map((table) => table.name),
      contains(UnifiedDatabase.diagnosticsScratchTable),
    );

    await database.dropDiagnosticsScratchTable();
    expect(
      (await database.inspect()).tables.map((table) => table.name),
      isNot(contains(UnifiedDatabase.diagnosticsScratchTable)),
    );
  });

  test(
    'clearing all local data preserves schema and reports deleted rows',
    () async {
      final database = createDatabase();
      await database.writeSettingValue(
        id: 'test-setting',
        group: 'test',
        value: '1',
      );
      await database.insertDiagnosticRecord(
        id: 'clear-all-record',
        title: 'clear all',
        payload: const <String, Object?>{},
      );

      final deleted = await database.clearAllLocalData();
      final overview = await database.inspect();

      expect(deleted['Settings'], 1);
      expect(deleted[UnifiedDatabase.diagnosticsTable], 1);
      expect(
        overview.tables.map((table) => table.name),
        containsAll(<String>['Settings', 'Messages', 'Friends']),
      );
      expect(overview.tables.every((table) => table.rowCount == 0), isTrue);
    },
  );
}
