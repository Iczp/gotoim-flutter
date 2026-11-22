import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/database/unified_database.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';
import 'package:gotoim_flutter/features/chat/data/datasources/message_api.dart';
import 'package:gotoim_flutter/features/chat/data/datasources/message_dao.dart';
import 'package:gotoim_flutter/features/chat/data/models/chat_message.dart';
import 'package:gotoim_flutter/features/chat/data/repositories/message_repository.dart';

class _FakeApiClient implements ApiClient {
  final List<String> paths = [];
  Map<String, dynamic> Function(String path, Map<String, Object?>? query)? onGet;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    bool retryOnUnauthorized = true,
  }) async {
    paths.add(path);
    if (onGet != null) {
      return onGet!(path, query) as T;
    }
    return <String, dynamic>{} as T;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const ownerId = 1001;
  const sessionUnitId = 'test_session_unit_1';

  ChatMessage buildMsg(int id) => ChatMessage.fromJson(
    <String, dynamic>{
      'id': id,
      'clientMessageId': 'c$id',
      'messageType': 0,
      'creationTime': '2026-11-22T10:00:0${id % 10}Z',
      'content': <String, dynamic>{'text': 'Msg $id'},
    },
    ownerId: ownerId,
    sessionUnitId: sessionUnitId,
  );

  test('UnifiedDatabase: readAroundAnchorMessageRows and readNewerMessageRows', () async {
    final db = UnifiedDatabase(
      DatabaseConnection(NativeDatabase.memory()),
    );
    addTearDown(db.close);
    final dao = MessageDao(db);

    // Insert 10 sequential messages
    await dao.upsertAll([
      for (var i = 1; i <= 10; i++) buildMsg(100 + i),
    ]);

    // Query around anchor 105
    final sliceRaw = await db.readAroundAnchorMessageRows(
      ownerId: ownerId,
      sessionUnitId: sessionUnitId,
      targetServerId: 105,
      beforeCount: 2,
      afterCount: 2,
    );

    final anchor = sliceRaw['anchor'] as Map<String, Object?>?;
    final before = sliceRaw['before'] as List<Map<String, Object?>>;
    final after = sliceRaw['after'] as List<Map<String, Object?>>;

    expect(anchor, isNotNull);
    expect(anchor!['serverId'], 105);
    expect(before.map((r) => r['serverId']).toList(), contains(104));
    expect(after.map((r) => r['serverId']).toList(), contains(106));

    // Query newer messages after score of 105
    final anchorScore = (anchor['score'] as num).toInt();
    final newerRows = await db.readNewerMessageRows(
      ownerId: ownerId,
      sessionUnitId: sessionUnitId,
      afterScore: anchorScore,
      limit: 3,
    );

    expect(newerRows.length, 3);
    expect(newerRows.map((r) => r['serverId']).toList(), [106, 107, 108]);
  });

  test('MessageRepository: getAroundAnchorSlice returns balanced items and targetIndex', () async {
    final db = UnifiedDatabase(
      DatabaseConnection(NativeDatabase.memory()),
    );
    addTearDown(db.close);
    final dao = MessageDao(db);

    await dao.upsertAll([
      for (var i = 1; i <= 10; i++) buildMsg(200 + i),
    ]);

    final client = _FakeApiClient();
    final repo = MessageRepository(api: MessageApi(client), dao: dao);

    final result = await repo.getAroundAnchorSlice(
      ownerId: ownerId,
      sessionUnitId: sessionUnitId,
      targetServerId: 205,
      beforeCount: 2,
      afterCount: 2,
    );

    expect(client.paths, isEmpty); // 完全走本地缓存秒开
    expect(result.anchor, isNotNull);
    expect(result.anchor?.serverId, 205);
    expect(result.items.map((m) => m.serverId).toList(), [203, 204, 205, 206, 207]);
    expect(result.targetIndex, 2);
    expect(result.hasMoreOlder, isTrue);
    expect(result.hasMoreNewer, isTrue);
  });

  test('MessageRepository: getAroundAnchorSlice falls back to API when anchor missing locally', () async {
    final db = UnifiedDatabase(
      DatabaseConnection(NativeDatabase.memory()),
    );
    addTearDown(db.close);
    final dao = MessageDao(db);

    final client = _FakeApiClient();
    client.onGet = (path, query) {
      if (path.contains('/history')) {
        return {
          'items': [
            {
              'id': 302,
              'clientMessageId': 'c302',
              'creationTime': '2026-11-22T10:00:02Z',
              'content': {'text': '302'},
            },
            {
              'id': 303,
              'clientMessageId': 'c303',
              'creationTime': '2026-11-22T10:00:03Z',
              'content': {'text': '303'},
            },
          ],
          'hasMore': false,
        };
      } else if (path.contains('/latest')) {
        return {
          'items': [
            {
              'id': 304,
              'clientMessageId': 'c304',
              'creationTime': '2026-11-22T10:00:04Z',
              'content': {'text': '304'},
            },
          ],
          'hasMore': false,
        };
      }
      return {'items': []};
    };

    final repo = MessageRepository(api: MessageApi(client), dao: dao);

    final result = await repo.getAroundAnchorSlice(
      ownerId: ownerId,
      sessionUnitId: sessionUnitId,
      targetServerId: 303,
      beforeCount: 5,
      afterCount: 5,
    );

    expect(client.paths, contains('/api/chat/message/history'));
    expect(client.paths, contains('/api/chat/message/latest'));
    expect(result.anchor?.serverId, 303);
    expect(result.items.map((m) => m.serverId).toList(), [302, 303, 304]);
    expect(result.targetIndex, 1);
  });
}
