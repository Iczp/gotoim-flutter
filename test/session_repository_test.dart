import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/database/unified_database.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';
import 'package:gotoim_flutter/features/session/data/datasources/session_dao.dart';
import 'package:gotoim_flutter/features/session/data/datasources/session_unit_api.dart';
import 'package:gotoim_flutter/features/session/data/models/session_summary.dart';
import 'package:gotoim_flutter/features/session/data/repositories/session_repository.dart';

void main() {
  SessionSummary item(String id, int score) => SessionSummary.fromJson({
    'id': id,
    'ownerId': 7,
    'score': score,
    'ticks': score,
    'destination': {'name': id},
  });

  test('loadFriends returns a complete local page without HTTP', () async {
    final database = UnifiedDatabase(
      DatabaseConnection(NativeDatabase.memory()),
    );
    addTearDown(database.close);
    final dao = SessionDao(database);
    await dao.upsertAll([item('a', 2), item('b', 1)]);
    final client = _FakeApiClient();
    final repository = SessionRepository(api: SessionUnitApi(client), dao: dao);

    final result = await repository.loadFriends(ownerId: 7, limit: 2);

    expect(result.items.map((item) => item.id), ['a', 'b']);
    expect(client.getPaths, isEmpty);
  });

  test(
    'loadChanges only calls changes and persists returned friends',
    () async {
      final database = UnifiedDatabase(
        DatabaseConnection(NativeDatabase.memory()),
      );
      addTearDown(database.close);
      final dao = SessionDao(database);
      await dao.upsertAll([item('old', 100)]);
      final client = _FakeApiClient(
        responses: {
          '/api/chat/session-unit-cache/changes': {
            'items': [
              {
                'id': 'changed',
                'ownerId': 7,
                'score': 101,
                'ticks': 101,
                'destination': {'name': 'changed'},
              },
            ],
            'totalCount': 1,
          },
        },
      );
      final repository = SessionRepository(
        api: SessionUnitApi(client),
        dao: dao,
      );

      await repository.loadChanges(ownerId: 7);

      expect(client.getPaths, ['/api/chat/session-unit-cache/changes']);
      expect(
        (await dao.readPage(ownerId: 7)).map((item) => item.id),
        contains('changed'),
      );
    },
  );

  test('loadFriends exposes the server total count', () async {
    final database = UnifiedDatabase(
      DatabaseConnection(NativeDatabase.memory()),
    );
    addTearDown(database.close);
    final client = _FakeApiClient(
      responses: {
        '/api/chat/session-unit-cache/friends': {
          'items': [
            {
              'id': 'remote',
              'ownerId': 7,
              'score': 10,
              'ticks': 10,
              'destination': {'name': 'remote'},
            },
          ],
          'totalCount': 125,
        },
      },
    );
    final repository = SessionRepository(
      api: SessionUnitApi(client),
      dao: SessionDao(database),
    );

    final result = await repository.loadFriends(ownerId: 7, limit: 2);

    expect(result.totalCount, 125);
    expect(result.items.single.id, 'remote');
  });
}

class _FakeApiClient implements ApiClient {
  _FakeApiClient({this.responses = const {}});
  final Map<String, Map<String, dynamic>> responses;
  final List<String> getPaths = [];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    bool retryOnUnauthorized = true,
  }) async {
    getPaths.add(path);
    final response = responses[path];
    if (response == null) throw StateError('Unexpected GET $path');
    return response as T;
  }

  @override
  Future<T> post<T>(
    String path, {
    Map<String, Object?>? query,
    Object? data,
    Map<String, String>? headers,
    bool retryOnUnauthorized = true,
  }) => throw UnimplementedError();

  @override
  Future<void> cancelByTag(Object tag) async {}
}
