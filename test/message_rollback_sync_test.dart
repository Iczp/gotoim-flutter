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
import 'package:gotoim_flutter/features/session/data/session_change_bus.dart';

class _Client implements ApiClient {
  Object? failure;
  Map<String, dynamic> recent = {'items': <Object>[], 'totalCount': 0};
  final paths = <String>[];
  @override
  Future<T> post<T>(
    String path, {
    Map<String, Object?>? query,
    Object? data,
    Map<String, String>? headers,
    bool retryOnUnauthorized = true,
  }) async {
    paths.add(path);
    if (failure != null) throw failure!;
    return <String, dynamic>{'messageId': 101} as T;
  }

  @override
  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    bool retryOnUnauthorized = true,
  }) async {
    paths.add(path);
    return (path.endsWith('/history')
            ? recent
            : {'items': <Object>[], 'totalCount': 0})
        as T;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late UnifiedDatabase database;
  late MessageDao dao;
  late SessionDao sessions;
  late SessionChangeBus bus;
  late MessageRepository repository;
  late _Client client;
  final notices = <SessionChangeEvent>[];
  ChatMessage message(int id, {bool mine = false}) => ChatMessage.fromJson(
    {
      'id': id,
      'clientMessageId': 'client-$id',
      'senderSessionUnitId': mine ? 'unit' : 'peer',
      'messageType': 11,
      'creationTime': '2026-10-14T01:00:00Z',
      'senderName': '发送者',
      'content': {
        'items': [
          {'title': '文章$id', 'originalUrl': 'https://example.com/$id'},
        ],
      },
    },
    ownerId: 7,
    sessionUnitId: 'unit',
  );
  Future<ChatMessage> local(int id) async =>
      (await dao.findByServerId(
        ownerId: 7,
        sessionUnitId: 'unit',
        serverId: id,
      ))!;
  Map<String, dynamic> withdrawal(int id) => {
    'message': {
      'id': id,
      'messageType': 11,
      'isRollbacked': true,
      'rollbackTime': '2026-10-14T02:00:00Z',
      'clientMessageId': null,
      'content': null,
      'senderSessionUnit': null,
    },
  };

  setUp(() async {
    database = UnifiedDatabase(DatabaseConnection(NativeDatabase.memory()));
    dao = MessageDao(database);
    sessions = SessionDao(database);
    bus = SessionChangeBus();
    notices.clear();
    bus.events.listen(notices.add);
    client = _Client();
    repository = MessageRepository(
      api: MessageApi(client),
      dao: dao,
      sessionDao: sessions,
      sessionChangeBus: bus,
    );
    await sessions.upsertAll([
      SessionSummary.fromJson({
        'id': 'unit',
        'ownerId': 7,
        'publicBadge': 3,
        'lastMessage': message(101).raw,
        'lastMessageTime': '2026-10-14T01:00:00Z',
      }),
    ]);
  });
  tearDown(() async {
    await bus.dispose();
    await database.close();
  });

  test(
    'local recall persists state and publishes the exact message for every open view',
    () async {
      final original = message(101, mine: true);
      await dao.upsertAll([original]);
      final result = await repository.rollback(original);
      expect(client.paths.single, '/api/chat/message-sender/rollback/101');
      expect(result.isRollbacked, isTrue);
      expect((await local(101)).isRollbacked, isTrue);
      expect(notices.single.messageId, 101);
      expect((await sessions.readById('unit'))!.preview, '消息已撤回');
    },
  );

  test(
    'a rejected recall preserves the original bubble and exposes the server reason',
    () async {
      final original = message(101);
      await dao.upsertAll([original]);
      client.failure = const ApiException('超过撤回时限', statusCode: 403);
      await expectLater(
        repository.rollback(original),
        throwsA(
          isA<ApiException>().having(
            (error) => error.message,
            'reason',
            '超过撤回时限',
          ),
        ),
      );
      expect((await local(101)).isRollbacked, isFalse);
      expect(notices, isEmpty);
    },
  );

  test(
    'content-free withdrawal is merged into the original row and repeated events do not increase badges',
    () async {
      final original = message(101);
      await dao.upsertAll([original]);
      for (var n = 0; n < 2; n++) {
        final result = await repository.applyRealtimePayloadFromCachedSession(
          withdrawal(101),
          sessionUnitId: 'unit',
        );
        expect(result!.localId, original.localId);
        expect(result.senderName, original.senderName);
        expect(result.createdAt, original.createdAt);
        expect(result.articleItems.single.title, '文章101');
        expect(result.isRollbacked, isTrue);
      }
      expect((await dao.readPage(ownerId: 7, sessionUnitId: 'unit')).length, 1);
      expect((await sessions.readById('unit'))!.unreadCount, 3);
    },
  );

  test(
    'a delayed creation or cached history cannot resurrect a withdrawn message',
    () async {
      final original = message(101);
      await dao.upsertAll([original]);
      await repository.applyRealtimePayload(
        ownerId: 7,
        sessionUnitId: 'unit',
        payload: withdrawal(101),
      );
      final delayed = await repository.applyRealtimePayload(
        ownerId: 7,
        sessionUnitId: 'unit',
        payload: original.raw,
      );
      expect(delayed!.isRollbacked, isTrue);
      await dao.upsertAll([original]);
      expect((await local(101)).isRollbacked, isTrue);
      expect((await sessions.readById('unit'))!.preview, '消息已撤回');
    },
  );

  test(
    'withdrawing an older message preserves the actual last-message preview and ordering',
    () async {
      await dao.upsertAll([message(100), message(101)]);
      final before = (await sessions.readById('unit'))!;
      await repository.applyRealtimePayload(
        ownerId: 7,
        sessionUnitId: 'unit',
        payload: withdrawal(100),
      );
      final after = (await sessions.readById('unit'))!;
      expect(after.preview, before.preview);
      expect(after.score, before.score);
      expect(after.raw['lastMessage'], before.raw['lastMessage']);
      expect(notices.single.messageId, 100);
      expect((await local(100)).isRollbacked, isTrue);
    },
  );

  test(
    'withdrawal does not resurrect a deleted or never-loaded local message',
    () async {
      final result = await repository.applyRealtimePayload(
        ownerId: 7,
        sessionUnitId: 'unit',
        payload: withdrawal(101),
      );
      expect(result, isNull);
      expect(await dao.readPage(ownerId: 7, sessionUnitId: 'unit'), isEmpty);
      expect((await sessions.readById('unit'))!.preview, '消息已撤回');
      expect((await sessions.readById('unit'))!.unreadCount, 3);
      notices.clear();
      await repository.applyRealtimePayload(
        ownerId: 7,
        sessionUnitId: 'unit',
        payload: withdrawal(100),
      );
      expect(notices, isEmpty);
    },
  );

  test(
    'reconnect refreshes withdrawal state even when no larger message ID exists',
    () async {
      await dao.upsertAll([message(101)]);
      client.recent = {
        'items': [
          {
            ...message(101).raw,
            'isRollbacked': true,
            'rollbackTime': '2026-10-14T02:00:00Z',
          },
        ],
        'totalCount': 1,
      };
      final changed = await repository.loadLatest(
        ownerId: 7,
        sessionUnitId: 'unit',
        minMessageId: 101,
        refreshRecent: true,
      );
      expect(changed.single.isRollbacked, isTrue);
      expect((await local(101)).isRollbacked, isTrue);
      expect(client.paths, [
        '/api/chat/message/history',
        '/api/chat/message/latest',
      ]);
    },
  );
}
