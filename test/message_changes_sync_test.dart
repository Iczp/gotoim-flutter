import 'dart:convert';
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

String v2Cursor(String epoch, String seq) => jsonEncode({'epoch': epoch, 'seq': seq});

Map<String, dynamic> v2Head(
  String epoch,
  String headChangeId, {
  String lastAppliedChangeId = '0',
  bool initialized = false,
}) => {
  'epoch': epoch,
  'headChangeId': headChangeId,
  'lastAppliedChangeId': lastAppliedChangeId,
  'initialized': initialized,
};

Map<String, dynamic> v2Pull({
  required String epoch,
  required String headChangeId,
  required String nextCursor,
  bool more = false,
  bool reset = false,
  List<Map<String, dynamic>> items = const [],
}) => {
  'epoch': epoch,
  'headChangeId': headChangeId,
  'nextCursor': nextCursor,
  'hasMore': more,
  'resetRequired': reset,
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
      await dao.applySyncPage(
        1,
        '__message_change_v2__',
        [],
        cursor: v2Cursor('e1', '5'),
      );
      client.respond = (path, body) async {
        if (path.endsWith('/message-change/pull')) {
          return v2Pull(
            epoch: 'e1',
            headChangeId: '10',
            nextCursor: '10',
            items: [
              {
                'messageChangeId': '7',
                'sessionId': 'srv-1',
                'sessionUnitId': 'unit',
                'messageId': '6',
                'changeType': 'Updated',
              },
            ],
          );
        }
        if (path.endsWith('/by-ids')) {
          return {
            'items': [
              {
                'sessionUnitId': 'unit',
                'messageId': '6',
                'status': 'DeletedForMe',
                'messageChangeId': '7',
              },
            ],
          };
        }
        return {};
      };
      await repo.loadChanges(ownerId: 1, sessionUnitId: 'unit');
      await repo.loadChanges(ownerId: 1, sessionUnitId: 'unit');
      await dao.upsertAll([message(6)]);
      expect(await dao.readPage(ownerId: 1, sessionUnitId: 'unit'), hasLength(1));
      expect(
        (await dao.readPage(ownerId: 2, sessionUnitId: 'peer')).single.serverId,
        5,
      );
      expect(
        await dao.syncCursor(1, '__message_change_v2__'),
        v2Cursor('e1', '10'),
      );
    },
  );

  test(
    'calibration deletes only explicit tombstones and preserves omitted messages',
    () async {
      await dao.upsertAll([message(5), message(6)]);
      client.respond = (path, _) async {
        if (path.endsWith('/message-change/pull')) {
          return v2Pull(
            epoch: 'e1',
            headChangeId: '10',
            nextCursor: '0',
            reset: true,
          );
        }
        if (path.endsWith('/by-ids')) {
          return {
            'items': [
              {
                'sessionUnitId': 'unit',
                'messageId': '5',
                'status': 'DeletedForMe',
                'messageChangeId': '7',
              },
            ],
          };
        }
        return {};
      };
      await repo.loadChanges(ownerId: 1, sessionUnitId: 'unit');
      expect(
        (await dao.readPage(ownerId: 1, sessionUnitId: 'unit')).single.serverId,
        6,
      );
      expect(
        await dao.syncCursor(1, '__message_change_v2__'),
        v2Cursor('e1', '10'),
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
      client.respond = (path, body) async {
        if (path.endsWith('/by-ids')) {
          final requests = body['requests'] as List;
          expect((requests.first as Map)['messageIds'], ['5', '700']);
          return {
            'items': [
              {
                'sessionUnitId': 'unit',
                'messageId': '5',
                'status': 'Recalled',
                'messageChangeId': '7',
                'rollbackTime': '2026-10-14T02:00:00Z',
              },
            ],
          };
        }
        if (path.endsWith('/message-change/pull')) {
          final epoch = body['epoch']?.toString() ?? '';
          if (epoch.isEmpty) {
            return v2Pull(
              epoch: 'e1',
              headChangeId: '10',
              nextCursor: '0',
              reset: true,
            );
          }
          expect(body['afterMessageChangeId'], '10');
          return v2Pull(
            epoch: 'e1',
            headChangeId: '12',
            nextCursor: '12',
            items: [
              {
                'messageChangeId': '12',
                'sessionId': 'srv-1',
                'sessionUnitId': 'unit',
                'messageId': '700',
                'changeType': 'Recalled',
              },
            ],
          );
        }
        return {};
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
        await dao.syncCursor(1, '__message_change_v2__'),
        v2Cursor('e1', '10'),
      );

      // Next change pulls incremental
      await repo.loadChanges(ownerId: 1, sessionUnitId: 'unit');
      expect(
        (await dao.findByServerId(
          ownerId: 1,
          sessionUnitId: 'unit',
          serverId: 700,
        ))!.isRollbacked,
        isTrue,
      );
      expect(
        await dao.syncCursor(1, '__message_change_v2__'),
        v2Cursor('e1', '12'),
      );
    },
  );

  test(
    'empty incremental page advances cursor to headSeq',
    () async {
      await dao.upsertAll([message(2)]);
      await dao.applySyncPage(
        1,
        '__message_change_v2__',
        [],
        cursor: v2Cursor('e1', '5'),
      );
      client.respond = (path, body) async {
        if (path.endsWith('/message-change/pull')) {
          expect(body['afterMessageChangeId'], '5');
          return v2Pull(
            epoch: 'e1',
            headChangeId: '10',
            nextCursor: '10',
            items: [
              {
                'messageChangeId': '7',
                'sessionId': 'srv-1',
                'sessionUnitId': 'unit',
                'messageId': '2',
                'changeType': 'Recalled',
              },
            ],
          );
        }
        return {};
      };
      await repo.loadChanges(ownerId: 1, sessionUnitId: 'unit');
      expect(
        await dao.syncCursor(1, '__message_change_v2__'),
        v2Cursor('e1', '10'),
      );
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
    'global normal recovery checks one global cursor without uploading message ids',
    () async {
      await dao.upsertAll([message(5, unit: 'a'), message(6, unit: 'b')]);
      await dao.applySyncPage(
        1,
        '__message_change_v2__',
        [],
        cursor: v2Cursor('e1', '10'),
      );
      client.respond = (path, body) async {
        if (path.endsWith('/message-change/pull')) {
          expect(body.containsKey('messageIds'), isFalse);
          expect(body.containsKey('sessionUnitIds'), isFalse);
          return v2Pull(
            epoch: 'e1',
            headChangeId: '10',
            nextCursor: '10',
          );
        }
        return {};
      };
      await repo.loadChanges(ownerId: 1);
      expect(client.calls.length, 1);
      expect(
        await dao.syncCursor(1, '__message_change_v2__'),
        v2Cursor('e1', '10'),
      );
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
                statusCode: 404,
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

  test('incremental updated change refreshes message content and dims in local cache', () async {
    final original = message(100).copyWith(
      raw: {
        ...message(100).raw,
        'content': {'width': 1080, 'height': 1920},
      },
    );
    await dao.upsertAll([original]);
    await dao.applySyncPage(1, '__message_change_v2__', [], cursor: v2Cursor('e', '5'));

    client.respond = (path, body) async {
      if (path == '/api/chat/message-change/pull') {
        return v2Pull(
          epoch: 'e',
          headChangeId: '6',
          nextCursor: '6',
          items: [
            {
              'messageChangeId': '6',
              'sessionUnitId': 'unit',
              'messageId': 100,
              'changeType': 'Updated',
            },
          ],
        );
      }
      if (path == '/api/chat/message/by-ids') {
        return {
          'items': [
            {
              'sessionUnitId': 'unit',
              'messageId': '100',
              'status': 'Visible',
              'messageChangeId': '6',
              'message': {
                'id': 100,
                'sessionUnitId': 'unit',
                'ownerId': 1,
                'creationTime': '2026-11-20T00:00:00Z',
                'content': {'width': 1920, 'height': 1080},
              },
            },
          ],
        };
      }
      if (path == '/api/chat/message-change/ack') {
        return <String, dynamic>{'acknowledged': true};
      }
      throw UnimplementedError('Unexpected path: $path');
    };

    await repo.loadChanges(ownerId: 1);

    final updated = await dao.findByServerId(ownerId: 1, sessionUnitId: 'unit', serverId: 100);
    expect(updated, isNotNull);
    expect(updated!.content['width'], 1920);
    expect(updated.content['height'], 1080);
  });
}
