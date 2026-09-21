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

  test('session summary parses PascalCase DTO fields from backend', () {
    final summary = SessionSummary.fromJson(<String, dynamic>{
      'Id': 'bd95c9bf-e3df-48ea-6f69-3a23b4fd2e58',
      'OwnerId': 42,
      'Score': 9876543210,
      'Sorting': 5,
      'Ticks': 123456789,
      'PublicBadge': 2,
      'Destination': <String, dynamic>{'DisplayName': 'Aurora AI'},
      'Setting': <String, dynamic>{'IsTopping': true},
    });

    expect(summary.id, 'bd95c9bf-e3df-48ea-6f69-3a23b4fd2e58');
    expect(summary.ownerId, 42);
    expect(summary.score, 9876543210);
    expect(summary.sorting, 5);
    expect(summary.ticks, 123456789);
    expect(summary.unreadCount, 2);
    expect(summary.isPinned, isTrue);
    expect(summary.title, 'Aurora AI');
  });

  test('mergeWithLocal retains score fields for a partial state response', () {
    final local = SessionSummary.fromJson(<String, dynamic>{
      'id': 'unit-test-1',
      'ownerId': 42,
      'score': 100000000500,
      'sorting': 1,
      'ticks': 500,
      'publicBadge': 0,
      'readMessageId': 9999,
      'destination': <String, dynamic>{'displayName': '好友A'},
      'lastMessage': <String, dynamic>{
        'id': 9999,
        'content': <String, dynamic>{'text': '你好'},
      },
    });

    // A state acknowledgement omits the FriendScore tuple.
    final remoteFriendDetail = SessionSummary.fromJson(<String, dynamic>{
      'id': 'unit-test-1',
      'ownerId': 42,
      'lastMessageId': 9999,
      'publicBadge': 5, // Stale server unread count
      'destination': <String, dynamic>{'displayName': '好友A（最新）'},
    });

    final merged = remoteFriendDetail.mergeWithLocal(local);

    // Missing score fields must not wipe the local tuple.
    expect(merged.score, 100000000500);
    expect(merged.sorting, 1);
    expect(merged.ticks, 500);
    expect(merged.isPinned, isTrue);
    expect(merged.title, '好友A（最新）');
    expect(merged.preview, '你好');
    // Unread count must not resurrect stale badge since local already read past 9999
    expect(merged.unreadCount, 0);
  });

  test('mergeWithLocal accepts a lower authoritative FriendScore tuple', () {
    final local = SessionSummary.fromJson(<String, dynamic>{
      'id': 'unit-test-1',
      'ownerId': 42,
      'score': 100000000500,
      'sorting': 1,
      'ticks': 500,
    });
    final remoteDetail = SessionSummary.fromJson(<String, dynamic>{
      'id': 'unit-test-1',
      'ownerId': 42,
      'score': 600,
      'sorting': 0,
      'ticks': 600,
    });

    final merged = remoteDetail.mergeWithLocal(local);

    expect(merged.score, 600);
    expect(merged.sorting, 0);
    expect(merged.ticks, 600);
    expect(merged.isPinned, isFalse);
  });

  test(
    'session DAO persists and restores sorting and score correctly',
    () async {
      final database = UnifiedDatabase(
        DatabaseConnection(NativeDatabase.memory()),
      );
      addTearDown(database.close);
      final dao = SessionDao(database);
      final summary = SessionSummary.fromJson(<String, dynamic>{
        'id': 'unit-sort-1',
        'ownerId': 42,
        'score': 5000000000,
        'sorting': 2,
        'ticks': 999999,
        'destination': <String, dynamic>{'displayName': '置顶好友'},
      });

      await dao.upsertAll(<SessionSummary>[summary]);
      final cached = await dao.readPage(ownerId: 42);

      expect(cached, hasLength(1));
      expect(cached.single.score, 5000000000);
      expect(cached.single.sorting, 2);
      expect(cached.single.ticks, 999999);
      expect(cached.single.isPinned, isTrue);
    },
  );

  test('message updates retain the FriendScore contract', () async {
    final database = UnifiedDatabase(
      DatabaseConnection(NativeDatabase.memory()),
    );
    addTearDown(database.close);
    final dao = SessionDao(database);
    await dao.upsertAll(<SessionSummary>[
      SessionSummary.fromJson(<String, dynamic>{
        'id': 'pinned-session',
        'ownerId': 42,
        'score': 90000000000000,
        'sorting': 9,
        'ticks': 1,
      }),
    ]);

    await dao.updateLastMessage(
      ownerId: 42,
      sessionUnitId: 'pinned-session',
      message: <String, dynamic>{
        'id': 7297803,
        'creationTime': '2026-09-21T01:00:00Z',
      },
    );

    final cached = await dao.readById('pinned-session');
    final ticks =
        DateTime.parse('2026-09-21T01:00:00Z').toLocal().millisecondsSinceEpoch;
    expect(cached?.ticks, ticks);
    expect(cached?.score, 9 * 10000000000000 + ticks);
    expect(cached?.isPinned, isTrue);
  });

  test('repairs legacy message scores before local session ordering', () async {
    final database = UnifiedDatabase(
      DatabaseConnection(NativeDatabase.memory()),
    );
    addTearDown(database.close);
    final dao = SessionDao(database);
    await dao.upsertAll(<SessionSummary>[
      SessionSummary.fromJson(<String, dynamic>{
        'id': 'legacy-pinned-session',
        'ownerId': 42,
        // The legacy bug persisted a message score here.
        'score': 7297803000000,
        'sorting': 9,
        'ticks': 1789894167339,
      }),
    ]);

    final repaired = await dao.repairScores(42);
    final cached = await dao.readById('legacy-pinned-session');

    expect(repaired, 1);
    expect(cached?.score, 9 * 10000000000000 + 1789894167339);
    expect(cached?.isPinned, isTrue);
  });
}
