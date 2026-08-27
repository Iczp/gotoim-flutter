import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/database/unified_database.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';
import 'package:gotoim_flutter/features/chat_settings/data/datasources/chat_member_api.dart';
import 'package:gotoim_flutter/features/chat_settings/data/datasources/chat_member_dao.dart';
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
}

class _FakeApiClient implements ApiClient {
  _FakeApiClient(this.response);
  final Map<String, dynamic> response;
  int getCount = 0;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    bool retryOnUnauthorized = true,
  }) async {
    getCount++;
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
