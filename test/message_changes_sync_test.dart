import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/database/unified_database.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';
import 'package:gotoim_flutter/core/network/api_exception.dart';
import 'package:gotoim_flutter/features/chat/data/datasources/message_api.dart';
import 'package:gotoim_flutter/features/chat/data/datasources/message_dao.dart';
import 'package:gotoim_flutter/features/chat/data/models/chat_message.dart';
import 'package:gotoim_flutter/features/chat/data/repositories/message_repository.dart';
import 'package:gotoim_flutter/features/session/data/datasources/session_dao.dart';
import 'package:gotoim_flutter/features/session/data/models/session_summary.dart';

class _Client implements ApiClient {
  final calls = <(String, Object?)>[];
  late Future<Object> Function(String, Map<String, dynamic>) respond;
  @override
  Future<T> post<T>(
    String path, {
    Map<String, Object?>? query,
    Object? data,
    Map<String, String>? headers,
    bool retryOnUnauthorized = true,
  }) async {
    calls.add((path, data));
    return await respond(path, Map<String, dynamic>.from(data as Map)) as T;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> page(
  String unit,
  String next, {
  bool reset = false,
  bool more = false,
  List<Map<String, dynamic>> items = const [],
}) => {
  'sessionUnitId': unit,
  'nextCursor': next,
  'snapshotCursor': 'snapshot',
  'resetRequired': reset,
  'hasMore': more,
  'items': items,
};
Map<String, dynamic> recalled(int id, int version) => {
  'messageId': '$id',
  'syncVersion': '$version',
  'changeType': 1,
  'isRollbacked': true,
  'rollbackTime': '2026-10-14T02:00:00Z',
};
ChatMessage message(int id, {String unit = 'unit', int owner = 1}) =>
    ChatMessage.fromJson(
      {
        'id': id,
        'messageType': 0,
        'creationTime': '2026-10-01T01:00:00Z',
        'content': {'text': 'message $id'},
      },
      ownerId: owner,
      sessionUnitId: unit,
    );

void main() {
  late UnifiedDatabase db;
  late MessageDao dao;
  late _Client client;
  late MessageRepository repo;
  setUp(() async {
    db = UnifiedDatabase(DatabaseConnection(NativeDatabase.memory()));
    dao = MessageDao(db);
    client = _Client();
    repo = MessageRepository(api: MessageApi(client), dao: dao);
    await db.initialize();
  });
  tearDown(() => db.close());

  test(
    'delete replay removes only the affected identity and cannot be resurrected by old history',
    () async {
      await dao.upsertAll([
        message(5),
        message(6),
        message(5, owner: 2, unit: 'peer'),
      ]);
      final sessions = SessionDao(db);
      await sessions.upsertAll([
        SessionSummary.fromJson({
          'id': 'unit',
          'ownerId': 1,
          'lastMessage': message(6).raw,
        }),
      ]);
      await dao.applySyncPage(1, 'unit', [], cursor: 'start');
      client.respond =
          (_, _) async => [
            page(
              'unit',
              'done',
              items: [
                {
                  'messageId': '6',
                  'syncVersion': '7',
                  'changeType': 2,
                  'isDeleted': true,
                },
                {
                  'messageId': '5',
                  'syncVersion': '8',
                  'changeType': 2,
                  'isDeleted': true,
                },
              ],
            ),
          ];
      await repo.loadChanges(ownerId: 1, sessionUnitId: 'unit');
      await repo.loadChanges(ownerId: 1, sessionUnitId: 'unit');
      await dao.upsertAll([message(5), message(6)]);
      expect(await dao.readPage(ownerId: 1, sessionUnitId: 'unit'), isEmpty);
      expect(
        (await dao.readPage(ownerId: 2, sessionUnitId: 'peer')).single.serverId,
        5,
      );
      expect((await sessions.readById('unit'))!.preview, isEmpty);
      // A stale Friend response must not restore a deleted preview either.
      await sessions.upsertAll([
        SessionSummary.fromJson({
          'id': 'unit',
          'ownerId': 1,
          'lastMessage': message(6).raw,
        }),
      ]);
      expect((await sessions.readById('unit'))!.preview, isEmpty);
      expect(await dao.syncCursor(1, 'unit'), 'done');
    },
  );

  test(
    'calibration deletes only explicit tombstones and preserves omitted messages',
    () async {
      await dao.upsertAll([message(5), message(6)]);
      var query = 0;
      client.respond = (path, _) async {
        if (path.endsWith('/sync-items')) {
          return [
            {'messageId': '5', 'syncVersion': '7', 'isDeleted': true},
          ];
        }
        return [page('unit', 'baseline', reset: ++query == 1)];
      };
      await repo.loadChanges(ownerId: 1, sessionUnitId: 'unit');
      expect(
        (await dao.readPage(ownerId: 1, sessionUnitId: 'unit')).single.serverId,
        6,
      );
    },
  );

  test(
    'delete redacts quotes and moves the summary to the next cached message',
    () async {
      final sessions = SessionDao(db);
      final quoting = message(7).copyWith(
        raw: {
          ...message(7).raw,
          'quoteMessageId': 5,
          'quoteMessage': message(5).raw,
        },
      );
      await dao.upsertAll([message(5), quoting]);
      await sessions.upsertAll([
        SessionSummary.fromJson({
          'id': 'unit',
          'ownerId': 1,
          'lastMessage': message(5).raw,
        }),
      ]);
      await dao.applySyncPage(1, 'unit', [
        {'messageId': '5', 'syncVersion': '8', 'isDeleted': true},
      ], cursor: 'done');
      final row =
          (await dao.readPage(ownerId: 1, sessionUnitId: 'unit')).single;
      expect(row.quoteMessage['isDeleted'], isTrue);
      expect(row.quoteMessage['content'], isNull);
      expect((await sessions.readById('unit'))!.raw['lastMessage']['id'], 7);
      await dao.upsertAll([quoting]);
      expect(
        (await dao.readPage(
          ownerId: 1,
          sessionUnitId: 'unit',
        )).single.quoteMessage['isDeleted'],
        isTrue,
      );
    },
  );

  test(
    'failed mixed deletion page rolls back removed rows and cursor',
    () async {
      await dao.upsertAll([message(5), message(6)]);
      await dao.applySyncPage(1, 'unit', [], cursor: 'start');
      await expectLater(
        dao.applySyncPage(1, 'unit', [
          {'messageId': '5', 'syncVersion': '7', 'isDeleted': true},
          {...recalled(6, 8), 'rollbackTime': <String, Object>{}},
        ], cursor: 'done'),
        throwsA(anything),
      );
      expect((await dao.readPage(ownerId: 1, sessionUnitId: 'unit')).length, 2);
      expect(await dao.syncCursor(1, 'unit'), 'start');
    },
  );

  test(
    'the same server and client IDs coexist in different member caches',
    () async {
      final payload = {
        'id': 5,
        'clientMessageId': 'same-client',
        'content': {'text': 'hello'},
      };
      await dao.upsertAll([
        ChatMessage.fromJson(payload, ownerId: 1, sessionUnitId: 'unit'),
        ChatMessage.fromJson(payload, ownerId: 2, sessionUnitId: 'peer'),
      ]);
      expect(
        (await dao.readPage(ownerId: 1, sessionUnitId: 'unit')).single.text,
        'hello',
      );
      expect(
        (await dao.readPage(ownerId: 2, sessionUnitId: 'peer')).single.text,
        'hello',
      );
    },
  );

  test(
    'compact responses retain legacy local identity and sender avatar metadata',
    () async {
      final original = ChatMessage(
        localId: 'old-local-id',
        serverId: 5,
        clientMessageId: 'client-5',
        ownerId: 1,
        sessionUnitId: 'unit',
        senderSessionUnitId: 'peer',
        messageType: 0,
        state: 'received',
        score: 5000000,
        createdAt: DateTime(2026, 10, 1),
        raw: {
          'id': 5,
          'senderSessionUnit': {
            'id': 'peer',
            'owner': {'thumbnail': '/avatar.png', 'displayName': '张三'},
          },
          'content': {'text': 'hello'},
        },
      );
      await dao.upsertAll([original]);
      await dao.upsertAll([
        ChatMessage.fromJson(
          {'id': 5, 'clientMessageId': 'client-5', 'senderSessionUnit': null},
          ownerId: 1,
          sessionUnitId: 'unit',
        ),
      ]);
      final current =
          (await dao.readPage(ownerId: 1, sessionUnitId: 'unit')).single;
      expect(current.localId, 'old-local-id');
      expect(current.senderAvatarUrl, '/avatar.png');
      expect(current.senderSessionUnitId, 'peer');
      expect(current.text, 'hello');
    },
  );

  test(
    'bootstrap calibrates cached ids then replays changes committed during calibration',
    () async {
      await dao.upsertAll([message(5), message(700)]);
      var rounds = 0;
      client.respond = (path, body) async {
        if (path.endsWith('/sync-items')) {
          expect(body['messageIds'], [5, 700]);
          return [recalled(5, 0)];
        }
        final scope = (body['sessions'] as List).single as Map;
        rounds++;
        if (rounds == 1) {
          expect(scope['cursor'], isNull);
          return [page('unit', 'baseline', reset: true)];
        }
        expect(scope['cursor'], rounds == 2 ? 'baseline' : 'after');
        return [
          page('unit', 'after', items: rounds == 2 ? [recalled(700, 1)] : []),
        ];
      };
      await repo.loadChanges(ownerId: 1, sessionUnitId: 'unit');
      expect(
        (await dao.findByServerId(
          ownerId: 1,
          sessionUnitId: 'unit',
          serverId: 5,
        ))!.isRollbacked,
        isTrue,
      );
      expect(
        (await dao.findByServerId(
          ownerId: 1,
          sessionUnitId: 'unit',
          serverId: 700,
        ))!.isRollbacked,
        isTrue,
      );
      expect(await dao.syncCursor(1, 'unit'), 'after');
      await repo.loadChanges(ownerId: 1, sessionUnitId: 'unit');
      expect(
        client.calls.where((call) => call.$1.endsWith('/sync-items')).length,
        1,
      );
    },
  );

  test(
    'empty filtered page advances and preserves the snapshot for the next page',
    () async {
      await dao.upsertAll([message(2)]);
      await dao.applySyncPage(1, 'unit', [], cursor: 'start');
      var rounds = 0;
      client.respond = (_, body) async {
        final scope = (body['sessions'] as List).single as Map;
        if (++rounds == 1) return [page('unit', 'middle', more: true)];
        expect(scope['cursor'], 'middle');
        expect(scope['snapshotCursor'], 'snapshot');
        return [
          page('unit', 'finish', items: [recalled(2, 7)]),
        ];
      };
      await repo.loadChanges(ownerId: 1, sessionUnitId: 'unit');
      expect(await dao.syncCursor(1, 'unit'), 'finish');
      expect(
        (await dao.findByServerId(
          ownerId: 1,
          sessionUnitId: 'unit',
          serverId: 2,
        ))!.isRollbacked,
        isTrue,
      );
    },
  );

  test(
    'unimplemented future mutations do not acknowledge the cursor',
    () async {
      await dao.applySyncPage(1, 'unit', [], cursor: 'start');
      client.respond =
          (_, _) async => [
            page(
              'unit',
              'finish',
              items: [
                {'messageId': '5', 'changeType': 3},
              ],
            ),
          ];
      await expectLater(
        repo.loadChanges(ownerId: 1, sessionUnitId: 'unit'),
        throwsUnsupportedError,
      );
      expect(await dao.syncCursor(1, 'unit'), 'start');
    },
  );

  test(
    'a failed local page rolls back message flags, tombstones and cursor together',
    () async {
      await dao.upsertAll([message(5), message(6)]);
      await dao.applySyncPage(1, 'unit', [], cursor: 'start');
      await expectLater(
        dao.applySyncPage(1, 'unit', [
          recalled(5, 1),
          {...recalled(6, 2), 'rollbackTime': <String, Object>{}},
        ], cursor: 'finish'),
        throwsA(anything),
      );
      expect(await dao.syncCursor(1, 'unit'), 'start');
      expect(
        (await dao.findByServerId(
          ownerId: 1,
          sessionUnitId: 'unit',
          serverId: 5,
        ))!.isRollbacked,
        isFalse,
      );
      expect(await db.readMessageSyncCursor('', 2, 'unit'), isNull);
    },
  );

  test(
    'a tombstone for an unloaded message prevents a late stale insert',
    () async {
      await dao.applySyncPage(1, 'unit', [recalled(5, 3)], cursor: 'finish');
      expect(
        await dao.findByServerId(
          ownerId: 1,
          sessionUnitId: 'unit',
          serverId: 5,
        ),
        isNull,
      );
      await dao.upsertAll([message(5)]);
      final restored =
          (await dao.findByServerId(
            ownerId: 1,
            sessionUnitId: 'unit',
            serverId: 5,
          ))!;
      expect(restored.isRollbacked, isTrue);
      expect(restored.raw['content'], {'text': 'message 5'});
      final otherNamespace = MessageDao(db, syncNamespace: 'other-server');
      expect(await otherNamespace.syncCursor(1, 'unit'), isNull);
    },
  );

  test(
    'global normal recovery batches conversation cursors without uploading message ids',
    () async {
      await dao.upsertAll([message(5, unit: 'a'), message(6, unit: 'b')]);
      await dao.applySyncPage(1, 'a', [], cursor: 'a0');
      await dao.applySyncPage(1, 'b', [], cursor: 'b0');
      client.respond = (_, body) async {
        final scopes = body['sessions'] as List;
        expect(scopes.length, 2);
        expect(scopes.map((scope) => scope['cursor']), ['a0', 'b0']);
        expect(body.containsKey('messageIds'), isFalse);
        return [page('a', 'a1'), page('b', 'b1')];
      };
      await repo.loadChanges(ownerId: 1);
      expect(client.calls.length, 1);
      expect(await dao.syncCursor(1, 'a'), 'a1');
      expect(await dao.syncCursor(1, 'b'), 'b1');
    },
  );

  test(
    'server feature disabled leaves checkpoints intact and falls back quietly',
    () async {
      client.respond =
          (_, _) async =>
              throw const ApiException(
                'disabled',
                code: 'Chat:MessageChangeSyncDisabled',
                statusCode: 403,
              );
      await repo.loadChanges(ownerId: 1, sessionUnitId: 'unit');
      expect(repo.isChangeSyncAvailable, isFalse);
      expect(await dao.syncCursor(1, 'unit'), isNull);
      await repo.loadChanges(ownerId: 1, sessionUnitId: 'unit');
      expect(client.calls.length, 1);
    },
  );

  test(
    'quotes and last-message previews stay withdrawn after stale history and conversation responses',
    () async {
      final sessions = SessionDao(db);
      final original = message(5);
      final quote = message(9).copyWith(
        raw: {
          ...message(9).raw,
          'quoteMessageId': 5,
          'quoteMessage': original.raw,
        },
      );
      final summary = SessionSummary.fromJson({
        'id': 'unit',
        'ownerId': 1,
        'lastMessage': original.raw,
      });
      await dao.upsertAll([original, quote]);
      await sessions.upsertAll([summary]);
      await dao.applySyncPage(1, 'unit', [recalled(5, 3)], cursor: 'after');
      expect(
        (await dao.findByServerId(
          ownerId: 1,
          sessionUnitId: 'unit',
          serverId: 9,
        ))!.quoteMessage['isRollbacked'],
        isTrue,
      );
      expect((await sessions.readById('unit'))!.preview, '消息已撤回');
      await dao.upsertAll([original, quote]);
      await sessions.upsertAll([summary]);
      expect(
        (await dao.findByServerId(
          ownerId: 1,
          sessionUnitId: 'unit',
          serverId: 9,
        ))!.quoteMessage['isRollbacked'],
        isTrue,
      );
      expect((await sessions.readById('unit'))!.preview, '消息已撤回');
    },
  );

  test('malformed changes are rejected before acknowledging a page', () async {
    await dao.applySyncPage(1, 'unit', [], cursor: 'before');
    client.respond =
        (_, _) async => [
          page(
            'unit',
            'after',
            items: [
              {
                'messageId': 'bad',
                'syncVersion': '1',
                'changeType': 1,
                'isRollbacked': true,
              },
            ],
          ),
        ];
    await expectLater(
      repo.loadChanges(ownerId: 1, sessionUnitId: 'unit'),
      throwsFormatException,
    );
    expect(await dao.syncCursor(1, 'unit'), 'before');
  });
}
