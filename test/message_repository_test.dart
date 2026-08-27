import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/database/unified_database.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';
import 'package:gotoim_flutter/core/services/file/file_picker_service.dart';
import 'package:gotoim_flutter/features/chat/data/datasources/message_api.dart';
import 'package:gotoim_flutter/features/chat/data/datasources/message_dao.dart';
import 'package:gotoim_flutter/features/chat/data/models/chat_message.dart';
import 'package:gotoim_flutter/features/chat/data/repositories/message_repository.dart';
import 'package:gotoim_flutter/features/session/data/datasources/session_dao.dart';
import 'package:gotoim_flutter/features/session/data/models/session_summary.dart';
import 'package:gotoim_flutter/features/session/data/session_change_bus.dart';
import 'package:image_picker/image_picker.dart';

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

  test('message exposes sender nickname and avatar from senderSessionUnit', () {
    final value = ChatMessage.fromJson(
      <String, dynamic>{
        'id': 1,
        'messageType': 0,
        'senderSessionUnit': <String, dynamic>{
          'displayName': '成员昵称',
          'owner': <String, dynamic>{
            'fullPathName': '部门/张三',
            'thumbnail': '/avatars/1.png',
          },
        },
      },
      ownerId: 7,
      sessionUnitId: 'session',
    );

    expect(value.senderName, '部门:张三');
    expect(value.senderAvatarUrl, '/avatars/1.png');
  });

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

  test(
    'loadLatest persists and returns messages newer than minMessageId',
    () async {
      final database = UnifiedDatabase(
        DatabaseConnection(NativeDatabase.memory()),
      );
      addTearDown(database.close);
      final dao = MessageDao(database);
      final client = _FakeApiClient(<String, Map<String, dynamic>>{
        '/api/chat/message/latest': <String, dynamic>{
          'items': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 11,
              'clientMessageId': 'c11',
              'messageType': 0,
              'content': <String, dynamic>{'text': 'new'},
            },
          ],
          'totalCount': 1,
        },
      });
      final repository = MessageRepository(api: MessageApi(client), dao: dao);

      final latest = await repository.loadLatest(
        ownerId: 7,
        sessionUnitId: 'session',
        minMessageId: 10,
      );

      expect(latest.single.serverId, 11);
      expect(client.paths, <String>['/api/chat/message/latest']);
      expect(client.queries.single['minMessageId'], 10);
      expect(
        (await dao.readPage(
          ownerId: 7,
          sessionUnitId: 'session',
        )).single.serverId,
        11,
      );
    },
  );

  test(
    'file is persisted as sending before upload and updated in place',
    () async {
      final database = UnifiedDatabase(
        DatabaseConnection(NativeDatabase.memory()),
      );
      addTearDown(database.close);
      final temp = await File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}gotoim-file-message-test.txt',
      ).writeAsString('file payload');
      addTearDown(() => temp.delete());
      final selected = await SelectedFile.fromXFile(XFile(temp.path));
      final dao = MessageDao(database);
      final client =
          _FakeApiClient()
            ..multipartResponse = <String, dynamic>{
              'id': 88,
              'clientMessageId': 'server-client-id',
              'messageType': 5,
              'content': <String, dynamic>{
                'fileName': temp.uri.pathSegments.last,
                'size': await temp.length(),
                'suffix': '.txt',
              },
            };
      final repository = MessageRepository(api: MessageApi(client), dao: dao);

      final local = await repository.createLocalFile(
        ownerId: 7,
        sessionUnitId: 'session',
        file: selected,
      );
      final beforeUpload =
          (await dao.readPage(ownerId: 7, sessionUnitId: 'session')).single;

      expect(beforeUpload.localId, local.localId);
      expect(beforeUpload.state, 'sending');
      expect(beforeUpload.messageType, 5);
      expect(client.multipartPaths, isEmpty);

      final sent = await repository.sendLocalFile(local: local, file: selected);
      final afterUpload =
          (await dao.readPage(ownerId: 7, sessionUnitId: 'session')).single;

      expect(client.multipartPaths, <String>[
        '/api/chat/message-sender/send-upload-file/session',
      ]);
      expect(sent.localId, local.localId);
      expect(afterUpload.localId, local.localId);
      expect(afterUpload.serverId, 88);
      expect(afterUpload.state, 'sent');
    },
  );

  test('sent message updates friend summary and publishes change', () async {
    final database = UnifiedDatabase(
      DatabaseConnection(NativeDatabase.memory()),
    );
    addTearDown(database.close);
    final sessionDao = SessionDao(database);
    await sessionDao.upsertAll(<SessionSummary>[
      SessionSummary.fromJson(<String, dynamic>{
        'id': 'session',
        'ownerId': 7,
        'score': 1,
        'ticks': 1,
        'destination': <String, dynamic>{'name': '会话'},
      }),
    ]);
    final bus = SessionChangeBus();
    addTearDown(bus.dispose);
    final event = bus.events.first;
    final client =
        _FakeApiClient()
          ..postResponse = <String, dynamic>{
            'id': 99,
            'clientMessageId': 'client-99',
            'messageType': 0,
            'creationTime': '2026-08-27T09:00:00Z',
            'content': <String, dynamic>{'text': '新消息'},
          };
    final repository = MessageRepository(
      api: MessageApi(client),
      dao: MessageDao(database),
      sessionDao: sessionDao,
      sessionChangeBus: bus,
    );

    await repository.sendText(
      ownerId: 7,
      sessionUnitId: 'session',
      text: '新消息',
    );

    final friend = await sessionDao.readById('session');
    expect(friend?.preview, '新消息');
    expect(friend?.unreadCount, 0);
    expect((await event).sessionUnitId, 'session');
  });
}

class _FakeApiClient implements ApiClient {
  _FakeApiClient([this.responses = const <String, Map<String, dynamic>>{}]);
  final Map<String, Map<String, dynamic>> responses;
  final List<String> paths = <String>[];
  final List<Map<String, Object?>> queries = <Map<String, Object?>>[];
  final List<String> multipartPaths = <String>[];
  Map<String, dynamic>? multipartResponse;
  Map<String, dynamic>? postResponse;

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
  }) async => postResponse as T;

  @override
  Future<T> postMultipart<T>(
    String path, {
    Map<String, Object?>? query,
    required MultipartUploadFile file,
    String fieldName = 'file',
    bool retryOnUnauthorized = true,
  }) async {
    multipartPaths.add(path);
    return multipartResponse as T;
  }

  @override
  Future<void> cancelByTag(Object tag) async {}
}
