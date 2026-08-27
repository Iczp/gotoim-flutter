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

  test('loadFriends sends the last local maxMessageId to HTTP', () async {
    final database = UnifiedDatabase(
      DatabaseConnection(NativeDatabase.memory()),
    );
    addTearDown(database.close);
    final dao = SessionDao(database);
    await dao.upsertAll([
      SessionSummary.fromJson({
        'id': 'local',
        'ownerId': 7,
        'score': 20,
        'ticks': 20,
        'destination': {'name': 'local'},
        'lastMessage': {'id': 9001},
      }),
    ]);
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
          'totalCount': 2,
        },
      },
    );
    final repository = SessionRepository(api: SessionUnitApi(client), dao: dao);

    final localPage = await repository.loadFriends(ownerId: 7, limit: 1);
    expect(localPage.items.single.id, 'local');
    expect(client.getPaths, isEmpty);

    final result = await repository.loadFriends(
      ownerId: 7,
      limit: 1,
      cursor: const SessionCursor(id: 'local', score: 20, maxMessageId: 9001),
    );

    expect(result.items.single.id, 'remote');
    expect(client.getQueries.single['maxMessageId'], 9001);
    expect(client.getQueries.single['maxScore'], 20);
    expect(client.getQueries.single['cursorId'], 'local');
  });

  test('loadFriends keeps local rows when the remote page fails', () async {
    final database = UnifiedDatabase(
      DatabaseConnection(NativeDatabase.memory()),
    );
    addTearDown(database.close);
    final dao = SessionDao(database);
    await dao.upsertAll([item('cached', 20)]);
    final repository = SessionRepository(
      api: SessionUnitApi(_FakeApiClient()),
      dao: dao,
    );

    final result = await repository.loadFriends(ownerId: 7, limit: 2);

    expect(result.items.single.id, 'cached');
    expect(result.hasMore, isTrue);
  });

  test('remote owners are upserted and available offline', () async {
    final database = UnifiedDatabase(
      DatabaseConnection(NativeDatabase.memory()),
    );
    addTearDown(database.close);
    final dao = SessionDao(database);
    final repository = SessionRepository(
      api: SessionUnitApi(
        _FakeApiClient(
          responses: {
            '/api/chat/chat-object/by-current-user': {
              'items': [
                {
                  'id': 7,
                  'displayName': '本地身份',
                  'thumbnail': '/avatar.png',
                  'objectTypeDescription': '个人',
                },
              ],
              'totalCount': 1,
            },
          },
        ),
      ),
      dao: dao,
    );

    await repository.loadOwners();
    final cached = await repository.loadLocalOwners();

    expect(cached.single.id, 7);
    expect(cached.single.name, '本地身份');
    expect(cached.single.imageUrl, '/avatar.png');
  });

  test('remote friend detail updates the local friend row', () async {
    final database = UnifiedDatabase(
      DatabaseConnection(NativeDatabase.memory()),
    );
    addTearDown(database.close);
    final dao = SessionDao(database);
    final repository = SessionRepository(
      api: SessionUnitApi(
        _FakeApiClient(
          responses: {
            '/api/chat/session-unit-cache/friend/session-1': {
              'id': 'session-1',
              'ownerId': 7,
              'score': 12,
              'ticks': 12,
              'destination': {'displayName': '网络新标题'},
            },
          },
        ),
      ),
      dao: dao,
    );

    final remote = await repository.loadRemoteFriendDetail(
      ownerId: 7,
      sessionUnitId: 'session-1',
    );
    final local = await repository.loadLocalFriendDetail('session-1');

    expect(remote.title, '网络新标题');
    expect(local?.title, '网络新标题');
  });
}

class _FakeApiClient implements ApiClient {
  _FakeApiClient({this.responses = const {}});
  final Map<String, Map<String, dynamic>> responses;
  final List<String> getPaths = [];
  final List<Map<String, Object?>> getQueries = [];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    bool retryOnUnauthorized = true,
  }) async {
    getPaths.add(path);
    getQueries.add(query ?? const {});
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
  Future<T> postMultipart<T>(
    String path, {
    Map<String, Object?>? query,
    required MultipartUploadFile file,
    String fieldName = 'file',
    bool retryOnUnauthorized = true,
  }) => throw UnimplementedError();

  @override
  Future<void> cancelByTag(Object tag) async {}
}
