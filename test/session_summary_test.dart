import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/database/unified_database.dart';
import 'package:gotoim_flutter/features/session/data/datasources/session_dao.dart';
import 'package:gotoim_flutter/features/session/data/models/paged_result_dto.dart';
import 'package:gotoim_flutter/features/session/data/models/session_summary.dart';

void main() {
  test('session summary maps the UniApp friend DTO fields', () {
    final summary = SessionSummary.fromJson(<String, dynamic>{
      'id': 'unit-1',
      'ownerId': 42,
      'score': 100,
      'publicBadge': 3,
      'setting': <String, dynamic>{'isTopping': true},
      'destination': <String, dynamic>{'displayName': 'Flutter Team'},
      'lastMessage': <String, dynamic>{
        'content': <String, dynamic>{'text': '欢迎回来'},
        'creationTime': '2026-08-26T10:00:00Z',
      },
    });

    expect(summary.id, 'unit-1');
    expect(summary.title, 'Flutter Team');
    expect(summary.preview, '欢迎回来');
    expect(summary.unreadCount, 3);
    expect(summary.isPinned, isTrue);
  });

  test('paged result accepts an empty ABP page', () {
    final page = PagedResultDto<SessionSummary>.fromJson(<String, dynamic>{
      'items': <Object?>[],
      'totalCount': 0,
    }, SessionSummary.fromJson);

    expect(page.items, isEmpty);
    expect(page.totalCount, 0);
  });

  test('session DAO persists and restores a session summary', () async {
    final database = UnifiedDatabase(
      DatabaseConnection(NativeDatabase.memory()),
    );
    addTearDown(database.close);
    final dao = SessionDao(database);
    final summary = SessionSummary.fromJson(<String, dynamic>{
      'id': 'unit-1',
      'ownerId': 42,
      'score': 100,
      'ticks': 200,
      'destination': <String, dynamic>{'displayName': 'Flutter Team'},
      'lastMessage': <String, dynamic>{'content': '最新消息'},
    });

    await dao.upsertAll(<SessionSummary>[summary]);
    final cached = await dao.readPage(ownerId: 42);

    expect(cached, hasLength(1));
    expect(cached.single.id, summary.id);
    expect(cached.single.title, 'Flutter Team');
  });

  test(
    'session summary mergeWithLocal preserves local lastMessage when remote has none',
    () {
      final local = SessionSummary.fromJson(<String, dynamic>{
        'id': 'unit-1',
        'ownerId': 42,
        'destination': <String, dynamic>{'displayName': '张三'},
        'lastMessage': <String, dynamic>{
          'id': 7297000,
          'content': <String, dynamic>{'text': '本地最后一条消息'},
          'creationTime': '2026-08-26T10:00:00Z',
        },
        'lastMessageTime': '2026-08-26T10:00:00Z',
      });

      final remoteWithoutLastMessage = SessionSummary.fromJson(
        <String, dynamic>{
          'id': 'unit-1',
          'ownerId': 42,
          'destination': <String, dynamic>{'displayName': '张三（最新昵称）'},
          // 远端 friend detail 接口不返回 lastMessage
        },
      );

      final merged = remoteWithoutLastMessage.mergeWithLocal(local);

      expect(merged.title, '张三（最新昵称）');
      expect(merged.preview, '本地最后一条消息');
      expect(merged.lastMessageId, 7297000);
    },
  );

  test(
    'session summary mergeWithLocal keeps the local destination for partial state responses',
    () {
      final local = SessionSummary.fromJson(<String, dynamic>{
        'id': 'aurora-session',
        'ownerId': 42,
        'destination': <String, dynamic>{
          'displayName': 'Aurora AI',
          'thumbnail': 'https://example.test/aurora.png',
        },
      });
      final setReadResponse = SessionSummary.fromJson(<String, dynamic>{
        'id': 'aurora-session',
        'ownerId': 42,
        'owner': <String, dynamic>{'displayName': '当前发送人'},
        'readMessageId': 7297610,
      });

      final merged = setReadResponse.mergeWithLocal(local);

      expect(merged.title, 'Aurora AI');
      expect(merged.raw['destination'], local.raw['destination']);
      expect(merged.raw['owner'], <String, dynamic>{'displayName': '当前发送人'});
    },
  );

  test(
    'session summary fills a missing owner from CurrentObject without changing destination',
    () {
      final summary = SessionSummary.fromJson(<String, dynamic>{
        'id': 'aurora-session',
        'ownerId': 42,
        'destination': <String, dynamic>{'displayName': 'Aurora AI'},
      });

      final resolved = summary.withCurrentOwnerFallback(<String, dynamic>{
        'id': 42,
        'displayName': '当前发送人',
      });

      expect(resolved.raw['owner'], <String, dynamic>{
        'id': 42,
        'displayName': '当前发送人',
      });
      expect(resolved.title, 'Aurora AI');
    },
  );
}
