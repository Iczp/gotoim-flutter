import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/database/unified_database.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';
import 'package:gotoim_flutter/features/chat/data/datasources/message_dao.dart';
import 'package:gotoim_flutter/features/chat/data/models/chat_message.dart';
import 'package:gotoim_flutter/features/chat_settings/data/datasources/chat_member_api.dart';
import 'package:gotoim_flutter/features/chat_settings/data/datasources/chat_member_dao.dart';
import 'package:gotoim_flutter/features/chat_settings/data/models/chat_member.dart';
import 'package:gotoim_flutter/features/chat_settings/data/repositories/chat_settings_repository.dart';
import 'package:gotoim_flutter/features/session/data/datasources/session_dao.dart';
import 'package:gotoim_flutter/features/session/data/models/session_summary.dart';

void main() {
  test(
    'members load remotely, upsert locally and report total count',
    () async {
      final database = UnifiedDatabase(
        DatabaseConnection(NativeDatabase.memory()),
      );
      addTearDown(database.close);
      await SessionDao(database).upsertAll(<SessionSummary>[
        SessionSummary.fromJson(<String, dynamic>{
          'id': 'session',
          'ownerId': 7,
          'score': 1,
          'destination': <String, dynamic>{'name': '群聊'},
        }),
      ]);
      final client = _FakeApiClient(<String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'member-1',
            'score': 10,
            'owner': <String, dynamic>{'displayName': '张三'},
            'setting': <String, dynamic>{'isCreator': true},
          },
        ],
        'totalCount': 1,
      });
      final dao = ChatMemberDao(database);
      final repository = ChatSettingsRepository(
        api: ChatMemberApi(client),
        dao: dao,
      );

      final remote = await repository.loadMembers(
        ownerId: 7,
        sessionUnitId: 'session',
        limit: 30,
      );
      final local = await repository.loadMembers(
        ownerId: 7,
        sessionUnitId: 'session',
        limit: 30,
      );

      expect(remote.items.single.name, '张三');
      expect(remote.items.single.isCreator, isTrue);
      expect(remote.totalCount, 1);
      expect(local.items.single.id, 'member-1');
      expect(client.getCount, 1);
    },
  );

  test('clear messages resets local messages and friend summary', () async {
    final database = UnifiedDatabase(
      DatabaseConnection(NativeDatabase.memory()),
    );
    addTearDown(database.close);
    final sessionDao = SessionDao(database);
    await sessionDao.upsertAll(<SessionSummary>[
      SessionSummary.fromJson(<String, dynamic>{
        'id': 'session',
        'ownerId': 7,
        'score': 10,
        'publicBadge': 3,
        'lastMessage': <String, dynamic>{
          'id': 9,
          'content': <String, dynamic>{'text': '旧消息'},
        },
        'destination': <String, dynamic>{'name': '群聊'},
      }),
    ]);
    final messageDao = MessageDao(database);
    await messageDao.upsertAll(<ChatMessage>[
      ChatMessage.fromJson(
        <String, dynamic>{'id': 9, 'messageType': 0},
        ownerId: 7,
        sessionUnitId: 'session',
      ),
    ]);
    final repository = ChatSettingsRepository(
      api: ChatMemberApi(_FakeApiClient(<String, dynamic>{})),
      dao: ChatMemberDao(database),
    );

    await repository.clearMessages(7, 'session');

    expect(
      await messageDao.readPage(ownerId: 7, sessionUnitId: 'session'),
      isEmpty,
    );
    expect(await messageDao.isLoadedAll('session'), isFalse);
    final friend = await sessionDao.readById('session');
    expect(friend?.raw['lastMessage'], isNull);
    expect(friend?.unreadCount, 0);
  });

  test('member page continues from local cursor into remote page', () async {
    final database = UnifiedDatabase(
      DatabaseConnection(NativeDatabase.memory()),
    );
    addTearDown(database.close);
    final dao = ChatMemberDao(database);
    ChatMember member(String id, int score) =>
        ChatMember.fromJson(<String, dynamic>{
          'id': id,
          'score': score,
          'owner': <String, dynamic>{'displayName': id},
        });
    await dao.upsertAll(7, 'session', <ChatMember>[
      member('local-2', 20),
      member('local-1', 10),
    ]);
    final client = _FakeApiClient(<String, dynamic>{
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'remote-1',
          'score': 5,
          'owner': <String, dynamic>{'displayName': 'remote-1'},
        },
      ],
      'totalCount': 3,
      'extra': <String, dynamic>{'hasMore': false},
    });
    final repository = ChatSettingsRepository(
      api: ChatMemberApi(client),
      dao: dao,
    );

    final page = await repository.loadMembers(
      ownerId: 7,
      sessionUnitId: 'session',
      limit: 3,
    );

    expect(page.items.map((item) => item.id), <String>[
      'local-2',
      'local-1',
      'remote-1',
    ]);
    expect(page.hasMore, isFalse);
    expect(client.queries.single['maxScore'], 10);
    expect(client.queries.single['cursorId'], 'local-1');
  });
}

class _FakeApiClient implements ApiClient {
  _FakeApiClient(this.response);
  final Map<String, dynamic> response;
  int getCount = 0;
  final List<Map<String, Object?>> queries = <Map<String, Object?>>[];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    bool retryOnUnauthorized = true,
  }) async {
    getCount++;
    queries.add(query ?? const <String, Object?>{});
    return response as T;
  }

  @override
  Future<T> post<T>(
    String path, {
    Map<String, Object?>? query,
    Object? data,
    Map<String, String>? headers,
    bool retryOnUnauthorized = true,
  }) async => <String, dynamic>{} as T;

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
