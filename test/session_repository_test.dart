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

  test(
    'shopkeeper and shop waiter identities expose the transfer capability',
    () {
      final shopkeeper = SessionSummary.fromJson(<String, dynamic>{
        'id': 'shopkeeper',
        'destination': <String, dynamic>{'name': '店铺'},
        'ownerObjectType': 7,
      });
      final waiter = SessionSummary.fromJson(<String, dynamic>{
        'id': 'waiter',
        'destination': <String, dynamic>{'name': '客服'},
        'owner': <String, dynamic>{'objectType': 8},
      });
      final personal = SessionSummary.fromJson(<String, dynamic>{
        'id': 'person',
        'destination': <String, dynamic>{'name': '普通会话'},
        'ownerObjectType': 1,
      });

      expect(shopkeeper.isShopkeeperOrWaiter, isTrue);
      expect(waiter.isShopkeeperOrWaiter, isTrue);
      expect(personal.isShopkeeperOrWaiter, isFalse);
    },
  );

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

  test(
    'loadChanges does not erase a cached last message when omitted remotely',
    () async {
      final database = UnifiedDatabase(
        DatabaseConnection(NativeDatabase.memory()),
      );
      addTearDown(database.close);
      final dao = SessionDao(database);
      await dao.upsertAll([
        SessionSummary.fromJson({
          'id': 'aurora',
          'ownerId': 7,
          'score': 100,
          'ticks': 100,
          'destination': {'name': 'Aurora'},
          'lastMessage': {
            'id': 99,
            'content': {'text': '旧的 AI 回复'},
          },
        }),
      ]);
      final client = _FakeApiClient(
        responses: {
          '/api/chat/session-unit-cache/changes': {
            'items': [
              {
                'id': 'aurora',
                'ownerId': 7,
                'score': 101,
                'ticks': 101,
                'destination': {'name': 'Aurora'},
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

      expect((await dao.readById('aurora'))?.preview, '旧的 AI 回复');
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

  test(
    'contact index identity changes persist into offline friend cache',
    () async {
      final database = UnifiedDatabase(
        DatabaseConnection(NativeDatabase.memory()),
      );
      addTearDown(database.close);
      final dao = SessionDao(database);
      await dao.upsertAll(<SessionSummary>[
        SessionSummary.fromJson(<String, dynamic>{
          'id': 'friend-1',
          'ownerId': 7,
          'score': 10,
          'ticks': 10,
          'destination': <String, dynamic>{
            'displayName': '旧昵称',
            'thumbnail': '/old-avatar.png',
          },
        }),
      ]);
      final repository = SessionRepository(
        api: SessionUnitApi(_FakeApiClient()),
        dao: dao,
      );

      await repository.mergeContactIdentitySnapshots(
        ownerId: 7,
        snapshots: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'friend-1',
            'name': '新昵称',
            'thumbnail': '/new-avatar.png',
          },
        ],
      );

      final cached = await repository.loadLocalFriendDetail('friend-1');
      expect(cached?.title, '新昵称');
      expect(cached?.raw['destination'], isA<Map>());
      expect(
        (cached!.raw['destination'] as Map)['thumbnail'],
        '/new-avatar.png',
      );
    },
  );
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
    Map<String, Object?>? extraFields,
    required MultipartUploadFile file,
    String fieldName = 'file',
    void Function(int sent, int total)? onProgress,
    bool retryOnUnauthorized = true,
  }) => throw UnimplementedError();

  @override
  Future<void> cancelByTag(Object tag) async {}

  @override
  Future<List<int>> getBytes(
    String path, {
    Object? cancelTag,
    void Function(int received, int total)? onProgress,
  }) async => const <int>[];
}
