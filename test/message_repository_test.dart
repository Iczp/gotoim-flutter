import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/database/unified_database.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';
import 'package:gotoim_flutter/features/chat/data/datasources/message_api.dart';
import 'package:gotoim_flutter/features/chat/data/datasources/message_dao.dart';
import 'package:gotoim_flutter/features/chat/data/models/chat_message.dart';
import 'package:gotoim_flutter/features/chat/data/repositories/message_repository.dart';
import 'package:gotoim_flutter/features/session/data/datasources/session_dao.dart';
import 'package:gotoim_flutter/features/session/data/models/session_summary.dart';

void main() {
  ChatMessage message(int id) => ChatMessage.fromJson(
    <String, dynamic>{
      'id': id,
      'clientMessageId': 'c$id',
      'messageType': 0,
      'creationTime': '2026-08-27T08:00:00Z',
      'content': <String, dynamic>{'text': '$id'},
    },
    ownerId: 7,
    sessionUnitId: 'session',
  );

  test('history returns a complete local page without HTTP', () async {
    final database = UnifiedDatabase(
      DatabaseConnection(NativeDatabase.memory()),
    );
    addTearDown(database.close);
    final dao = MessageDao(database);
    await dao.upsertAll(<ChatMessage>[message(2), message(1)]);
    final client = _FakeApiClient();
    final repository = MessageRepository(api: MessageApi(client), dao: dao);

    final result = await repository.loadHistory(
      ownerId: 7,
      sessionUnitId: 'session',
      limit: 2,
    );

    expect(result.items.map((item) => item.serverId), <int?>[2, 1]);
    expect(client.paths, isEmpty);
  });

  test('initial load reads only ten local messages without HTTP', () async {
    final database = UnifiedDatabase(
      DatabaseConnection(NativeDatabase.memory()),
    );
    addTearDown(database.close);
    final dao = MessageDao(database);
    await dao.upsertAll(<ChatMessage>[
      for (var id = 1; id <= 15; id++) message(id),
    ]);
    final client = _FakeApiClient();
    final repository = MessageRepository(api: MessageApi(client), dao: dao);

    final result = await repository.loadInitialLocal(
      ownerId: 7,
      sessionUnitId: 'session',
    );

    expect(result.items.length, 10);
    expect(result.items.first.serverId, 15);
    expect(client.paths, isEmpty);
  });

  test(
    'history loads remote after local exhaustion with maxMessageId',
    () async {
      final database = UnifiedDatabase(
        DatabaseConnection(NativeDatabase.memory()),
      );
      addTearDown(database.close);
      final dao = MessageDao(database);
      await dao.upsertAll(<ChatMessage>[message(2)]);
      final client = _FakeApiClient(<String, Map<String, dynamic>>{
        '/api/chat/message/history': <String, dynamic>{
          'items': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 1,
              'clientMessageId': 'c1',
              'messageType': 0,
              'content': <String, dynamic>{'text': '1'},
            },
          ],
          'totalCount': 2,
        },
      });
      final repository = MessageRepository(api: MessageApi(client), dao: dao);

      final result = await repository.loadHistory(
        ownerId: 7,
        sessionUnitId: 'session',
        beforeScore: 2000000,
        limit: 1,
      );

      expect(result.items.single.serverId, 1);
      expect(client.queries.single['maxMessageId'], 2);
      expect(
        (await dao.readPage(ownerId: 7, sessionUnitId: 'session')).length,
        2,
      );
    },
  );

  test('empty remote history marks the friend loaded all', () async {
    final database = UnifiedDatabase(
      DatabaseConnection(NativeDatabase.memory()),
    );
    addTearDown(database.close);
    await SessionDao(database).upsertAll(<SessionSummary>[
      SessionSummary.fromJson(<String, dynamic>{
        'id': 'session',
        'ownerId': 7,
        'score': 1,
        'ticks': 1,
        'destination': <String, dynamic>{'name': 'session'},
      }),
    ]);
    final dao = MessageDao(database);
    final client = _FakeApiClient(<String, Map<String, dynamic>>{
      '/api/chat/message/history': <String, dynamic>{
        'items': <Map<String, dynamic>>[],
        'totalCount': 0,
      },
    });
    final repository = MessageRepository(api: MessageApi(client), dao: dao);

    final first = await repository.loadHistory(
      ownerId: 7,
      sessionUnitId: 'session',
    );
    final second = await repository.loadHistory(
      ownerId: 7,
      sessionUnitId: 'session',
    );

    expect(first.hasMore, isFalse);
    expect(second.hasMore, isFalse);
    expect(client.paths, <String>['/api/chat/message/history']);
    expect(await dao.isLoadedAll('session'), isTrue);
  });
}

class _FakeApiClient implements ApiClient {
  _FakeApiClient([this.responses = const <String, Map<String, dynamic>>{}]);
  final Map<String, Map<String, dynamic>> responses;
  final List<String> paths = <String>[];
  final List<Map<String, Object?>> queries = <Map<String, Object?>>[];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    bool retryOnUnauthorized = true,
  }) async {
    paths.add(path);
    queries.add(query ?? const <String, Object?>{});
    return responses[path] as T;
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
