import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/database/unified_database.dart';

void main() {
  UnifiedDatabase createDatabase() {
    final database = UnifiedDatabase(
      DatabaseConnection(NativeDatabase.memory()),
    );
    addTearDown(database.close);
    return database;
  }

  test('version 1 migrates the unified chat schema and indexes', () async {
    final database = createDatabase();

    final overview = await database.inspect();
    final tableNames = overview.tables.map((table) => table.name).toSet();

    expect(overview.name, UnifiedDatabase.databaseName);
    expect(overview.schemaVersion, 1);
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
}
