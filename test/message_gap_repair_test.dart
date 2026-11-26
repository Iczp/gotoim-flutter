import 'dart:async';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/database/unified_database.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';
import 'package:gotoim_flutter/core/network/api_exception.dart';
import 'package:gotoim_flutter/core/realtime/signalr_gateway.dart';
import 'package:gotoim_flutter/core/services/clipboard_service.dart';
import 'package:gotoim_flutter/core/services/file/attachment_transfer_service.dart';
import 'package:gotoim_flutter/core/services/file/file_picker_service.dart';
import 'package:gotoim_flutter/core/services/media/audio_playback_service.dart';
import 'package:gotoim_flutter/core/services/media/media_service.dart';
import 'package:gotoim_flutter/features/chat/application/ai_stream_change_bus.dart';
import 'package:gotoim_flutter/features/chat/application/chat_controller.dart';
import 'package:gotoim_flutter/features/chat/data/datasources/message_api.dart';
import 'package:gotoim_flutter/features/chat/data/datasources/message_dao.dart';
import 'package:gotoim_flutter/features/chat/data/models/chat_message.dart';
import 'package:gotoim_flutter/features/chat/data/repositories/message_repository.dart';
import 'package:gotoim_flutter/features/chat_settings/data/repositories/chat_settings_repository.dart';
import 'package:gotoim_flutter/features/session/data/models/session_summary.dart';
import 'package:gotoim_flutter/features/session/data/repositories/session_repository.dart';
import 'package:gotoim_flutter/features/session/data/session_change_bus.dart';

class _GapTestClient implements ApiClient {
  final latestMinMessageIds = <int>[];
  final historyCalls = <Object?>[];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    bool retryOnUnauthorized = true,
  }) async {
    if (path.endsWith('/message/latest')) {
      final minId = (query?['minMessageId'] as num?)?.toInt() ?? 0;
      latestMinMessageIds.add(minId);
      if (minId >= 7318641) {
        return {'items': [], 'extra': {'hasMore': false}} as T;
      }
      // Return the gap message 7318640 and the newest message 7318641
      return {
        'items': [
          {
            'id': 7318640,
            'sessionUnitId': 'unit',
            'senderSessionUnitId': 'other_unit',
            'content': {'text': 'message from peer 7318640'},
          },
          {
            'id': 7318641,
            'sessionUnitId': 'unit',
            'senderSessionUnitId': 'unit',
            'content': {'text': 'my message 7318641'},
          },
        ],
        'totalCount': 2,
      } as T;
    }
    if (path.endsWith('/message/history')) {
      historyCalls.add(query);
      return {
        'items': [
          {
            'id': 7318641,
            'sessionUnitId': 'unit',
            'senderSessionUnitId': 'unit',
            'content': {'text': 'my message 7318641'},
          },
          {
            'id': 7318640,
            'sessionUnitId': 'unit',
            'senderSessionUnitId': 'other_unit',
            'content': {'text': 'message from peer 7318640'},
          },
        ],
        'totalCount': 2,
      } as T;
    }
    return {'items': [], 'totalCount': 0} as T;
  }

  @override
  Future<T> post<T>(
    String path, {
    Map<String, Object?>? query,
    Object? data,
    Map<String, String>? headers,
    bool retryOnUnauthorized = true,
  }) async {
    if (path.endsWith('/message-change/pull')) {
      return {
        'epoch': 'epoch-1',
        'headChangeId': '0',
        'nextCursor': '0',
        'items': [],
      } as T;
    }
    return <String, Object?>{} as T;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sessions implements SessionRepository {
  final friend = SessionSummary.fromJson({
    'id': 'unit',
    'ownerId': 1,
    'readMessageId': 7318635,
    'destination': {'objectType': 1},
  });
  @override
  Future<SessionSummary?> loadLocalFriendDetail(String unit) async => friend;
  @override
  Future<SessionSummary> loadRemoteFriendDetail({
    required int ownerId,
    required String sessionUnitId,
  }) async => friend;
  @override
  Future<Map<String, dynamic>?> loadActiveAiRun({
    required String sessionUnitId,
  }) async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Gateway implements SignalRGateway {
  @override
  Stream<SignalRAppEvent> get events => const Stream.empty();
  @override
  SignalRConnectionState get connectionState =>
      SignalRConnectionState.connected;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Transfer extends ChangeNotifier implements AttachmentTransferService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Audio extends ChangeNotifier implements AudioPlaybackService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Files implements FilePickerService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Media implements MediaService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Clipboard implements ClipboardService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Settings implements ChatSettingsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ForbiddenClient implements ApiClient {
  @override
  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    bool retryOnUnauthorized = true,
  }) async {
    throw ApiException('Forbidden', statusCode: 403);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SnapshotVsForwardClient implements ApiClient {
  @override
  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    bool retryOnUnauthorized = true,
  }) async {
    if (path.endsWith('/message/history')) {
      return <String, dynamic>{
            'items': <dynamic>[
              <String, dynamic>{
                'id': 1000,
                'sessionUnitId': 'unit',
                'content': <String, dynamic>{
                  'text': 'recent snapshot message 1000',
                },
              },
            ],
            'totalCount': 1,
          }
          as T;
    }
    if (path.endsWith('/message/latest')) {
      final minId = (query?['minMessageId'] as num?)?.toInt() ?? 0;
      if (minId == 100) {
        return <String, dynamic>{
          'items': <dynamic>[
            <String, dynamic>{
              'id': 200,
              'sessionUnitId': 'unit',
              'content': <String, dynamic>{'text': 'forward message 200'},
            },
          ],
          'totalCount': 1,
        } as T;
      }
      return <String, dynamic>{'items': <dynamic>[], 'totalCount': 0} as T;
    }
    return <String, dynamic>{'items': <dynamic>[], 'totalCount': 0} as T;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecoveryClient implements ApiClient {
  final List<int> cursors = [];
  final List<int?> historyCursors = [];
  Completer<Map<String, dynamic>>? delayed;
  @override
  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    bool retryOnUnauthorized = true,
  }) async {
    if (path.endsWith('/history')) {
      historyCursors.add(query?['maxMessageId'] as int?);
      return {
            'items': [
              for (final id in [200, 150, 140])
                {
                  'id': id,
                  'content': {'text': '$id'},
                },
            ],
            'extra': {'hasMore': true},
          }
          as T;
    }
    final cursor = query?['minMessageId'] as int;
    cursors.add(cursor);
    if (delayed != null) return await delayed!.future as T;
    return {
          'items': [
            if (cursor < 3)
              {
                'id': cursor + 1,
                'content': {'text': 'recovered'},
              },
          ],
          'extra': {'hasMore': cursor < 2},
        }
        as T;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'message gap recovery: pulling uses contiguous sync watermark and recovers peer message 7318640 when 7318641 exists locally',
    () async {
      final database = UnifiedDatabase(
        DatabaseConnection(NativeDatabase.memory()),
      );
      addTearDown(database.close);
      final dao = MessageDao(database);

      // 1. Initial state: local has message 7318635, and watermark is 7318635
      final msg1 = ChatMessage.fromJson(
        {
          'id': 7318635,
          'content': {'text': 'initial message'},
        },
        ownerId: 1,
        sessionUnitId: 'unit',
      );
      await dao.upsertAll([msg1]);
      await dao.writeMessageWatermark(1, 'unit', 7318635);

      // 2. Client sent message 7318641 (e.g. offline/network delay for 7318640)
      // Local database now contains 7318641, but watermark is still 7318635!
      final myMsg = ChatMessage.fromJson(
        {
          'id': 7318641,
          'content': {'text': 'my message 7318641'},
        },
        ownerId: 1,
        sessionUnitId: 'unit',
      );
      await dao.upsertAll([myMsg]);

      // Verify local max server ID is 7318641, but watermark is 7318635
      expect(await dao.maxServerId(1, 'unit'), 7318641);
      expect(await dao.readMessageWatermark(1, 'unit'), 7318635);

      final client = _GapTestClient();
      final bus = SessionChangeBus();
      addTearDown(bus.dispose);
      final repo = MessageRepository(
        api: MessageApi(client),
        dao: dao,
        sessionChangeBus: bus,
      );

      // Safe sync cursor should return 7318635, NOT 7318641!
      final safeCursor = await repo.getLatestSyncCursor(
        ownerId: 1,
        sessionUnitId: 'unit',
      );
      expect(safeCursor, 7318635);

      final controller = ChatController(
        repo,
        _Sessions(),
        filePickerService: _Files(),
        attachmentTransferService: _Transfer(),
        mediaService: _Media(),
        audioPlaybackService: _Audio(),
        sessionChangeBus: bus,
        clipboardService: _Clipboard(),
        chatSettingsRepository: _Settings(),
        aiStreamChangeBus: AiStreamChangeBus(),
        signalRGateway: _Gateway(),
        ownerId: 1,
        sessionUnitId: 'unit',
        initialTitle: 'cached',
      );
      addTearDown(controller.dispose);

      // 3. Trigger loadLatest (as happens on reconnect or chat entry)
      await controller.loadLatest(refreshRecent: true);

      // 4. Verify:
      // The pull request used 7318635 (the watermark) so 7318640 was not skipped!
      expect(client.latestMinMessageIds, contains(7318635));

      // The lost message 7318640 is now successfully persisted locally in Drift!
      final recovered = await dao.findByServerId(
        ownerId: 1,
        sessionUnitId: 'unit',
        serverId: 7318640,
      );
      expect(recovered, isNotNull);
      expect(recovered!.text, 'message from peer 7318640');

      // The watermark has advanced to 7318641!
      expect(await dao.readMessageWatermark(1, 'unit'), 7318641);
    },
  );

  test('F1: getLatestSyncCursor does NOT write maxServerId as watermark when watermark is unset', () async {
    final database = UnifiedDatabase(
      DatabaseConnection(NativeDatabase.memory()),
    );
    addTearDown(database.close);
    final dao = MessageDao(database);

    final msg = ChatMessage.fromJson(
      {
        'id': 200,
        'content': {'text': 'realtime message 200'},
      },
      ownerId: 1,
      sessionUnitId: 'unit',
    );
    await dao.upsertAll([msg]);

    final repo = MessageRepository(
      api: MessageApi(_GapTestClient()),
      dao: dao,
    );

      final cursor = await repo.getLatestSyncCursor(
        ownerId: 1,
        sessionUnitId: 'unit',
      );
      // Cursor should return 0, and watermark in SQLite must remain unset/null!
      expect(cursor, 0);
      expect(await dao.readMessageWatermark(1, 'unit'), isNull);
    },
  );

  test('F2: loadLatest does NOT advance forward watermark to snapshot max ID', () async {
    final database = UnifiedDatabase(
      DatabaseConnection(NativeDatabase.memory()),
    );
    addTearDown(database.close);
    final dao = MessageDao(database);

    await dao.writeMessageWatermark(1, 'unit', 100);

      final client = _SnapshotVsForwardClient();
      final repo = MessageRepository(api: MessageApi(client), dao: dao);

    await repo.loadLatest(
      ownerId: 1,
      sessionUnitId: 'unit',
      minMessageId: 100,
      refreshRecent: true,
    );

      // Watermark must advance to 200 (forward progress), NOT 1000 (snapshot max)!
      final watermark = await dao.readMessageWatermark(1, 'unit');
      expect(watermark, 200);
    },
  );

  test('F3: loadHistory does NOT overwrite an existing watermark from history response', () async {
    final database = UnifiedDatabase(
      DatabaseConnection(NativeDatabase.memory()),
    );
    addTearDown(database.close);
    final dao = MessageDao(database);

    // Existing watermark is established at 500
    await dao.writeMessageWatermark(1, 'unit', 500);

      final client = _SnapshotVsForwardClient();
      final repo = MessageRepository(api: MessageApi(client), dao: dao);

      // Fetch initial history page where remote returns snapshot message with ID 1000
      await repo.loadHistory(ownerId: 1, sessionUnitId: 'unit');

      // Watermark must remain 500, not overwritten by 1000!
      final watermark = await dao.readMessageWatermark(1, 'unit');
      expect(watermark, 500);
    },
  );

  test('F4: ChatController loadLatest with refreshRecent fetches history snapshot for empty session', () async {
    final database = UnifiedDatabase(
      DatabaseConnection(NativeDatabase.memory()),
    );
    addTearDown(database.close);
    final dao = MessageDao(database);

    final client = _GapTestClient();
    final bus = SessionChangeBus();
    addTearDown(bus.dispose);
    final repo = MessageRepository(
      api: MessageApi(client),
      dao: dao,
      sessionChangeBus: bus,
    );

    final controller = ChatController(
      repo,
      _Sessions(),
      filePickerService: _Files(),
      attachmentTransferService: _Transfer(),
      mediaService: _Media(),
      audioPlaybackService: _Audio(),
      sessionChangeBus: bus,
      clipboardService: _Clipboard(),
      chatSettingsRepository: _Settings(),
      aiStreamChangeBus: AiStreamChangeBus(),
      signalRGateway: _Gateway(),
      ownerId: 1,
      sessionUnitId: 'unit',
      initialTitle: 'empty session',
    );
    addTearDown(controller.dispose);

    // Initial state: empty messages
    expect(controller.messages, isEmpty);

    // Reconnect/re-entry triggers loadLatest(refreshRecent: true)
    await controller.loadLatest(refreshRecent: true);

      // Verified: First messages are recovered and visible in controller!
      expect(controller.messages, isNotEmpty);
      expect(
        await dao.findByServerId(
          ownerId: 1,
          sessionUnitId: 'unit',
          serverId: 7318641,
        ),
        isNotNull,
      );
    },
  );

  test('F7: loadHistory on 403 Forbidden does NOT permanently mark loadedAll', () async {
    final database = UnifiedDatabase(
      DatabaseConnection(NativeDatabase.memory()),
    );
    addTearDown(database.close);
    final dao = MessageDao(database);

      final client = _ForbiddenClient();
      final repo = MessageRepository(api: MessageApi(client), dao: dao);

      final page = await repo.loadHistory(ownerId: 1, sessionUnitId: 'unit');

      expect(page.items, isEmpty);
      // Crucial: SQLite loadedAll flag must NOT be marked true!
      expect(await dao.isLoadedAll('unit'), isFalse);
    },
  );
  test(
    'missing watermark with newer cache recovers from zero and automatically continues',
    () async {
      final database = UnifiedDatabase(
        DatabaseConnection(NativeDatabase.memory()),
      );
      addTearDown(database.close);
      final dao = MessageDao(database);
      await dao.upsertAll([
        ChatMessage.fromJson({'id': 500}, ownerId: 1, sessionUnitId: 'unit'),
      ]);
      final client = _RecoveryClient();
      final repo = MessageRepository(api: MessageApi(client), dao: dao);
      addTearDown(repo.dispose);
      await repo.loadLatest(
        ownerId: 1,
        sessionUnitId: 'unit',
        minMessageId: await repo.getLatestSyncCursor(
          ownerId: 1,
          sessionUnitId: 'unit',
        ),
        limit: 1,
        maxPages: 1,
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(client.cursors, [0, 1, 2]);
      expect(await dao.readMessageWatermark(1, 'unit'), 3);
      expect(
        await dao.findByServerId(
          ownerId: 1,
          sessionUnitId: 'unit',
          serverId: 1,
        ),
        isNotNull,
      );
    },
  );

  test(
    'a full fragmented history page fetches from its requested boundary and persists coverage',
    () async {
      final database = UnifiedDatabase(
        DatabaseConnection(NativeDatabase.memory()),
      );
      addTearDown(database.close);
      final dao = MessageDao(database);
      await dao.upsertAll([
        for (final id in [200, 50])
          ChatMessage.fromJson({'id': id}, ownerId: 1, sessionUnitId: 'unit'),
      ]);
      final client = _RecoveryClient();
      final repo = MessageRepository(api: MessageApi(client), dao: dao);
      final page = await repo.loadHistory(
        ownerId: 1,
        sessionUnitId: 'unit',
        limit: 2,
      );
      expect(client.historyCursors, [null]);
      expect(page.items.map((m) => m.serverId), [200, 150]);
      expect(await dao.readMessageWatermark(1, 'unit'), isNull);
      await repo.loadHistory(ownerId: 1, sessionUnitId: 'unit', limit: 2);
      expect(client.historyCursors.length, 1);
    },
  );

  test(
    'disposing identity while HTTP is pending prevents both message and cursor writes',
    () async {
      final database = UnifiedDatabase(
        DatabaseConnection(NativeDatabase.memory()),
      );
      addTearDown(database.close);
      final dao = MessageDao(database);
      final client =
          _RecoveryClient()..delayed = Completer<Map<String, dynamic>>();
      final repo = MessageRepository(api: MessageApi(client), dao: dao);
      final pending = repo.loadLatest(
        ownerId: 1,
        sessionUnitId: 'unit',
        minMessageId: 0,
      );
      final assertion = expectLater(pending, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      repo.dispose();
      client.delayed!.complete({
        'items': [
          {'id': 1},
        ],
        'extra': {'hasMore': false},
      });
      await assertion;
      expect(await dao.readMessageWatermark(1, 'unit'), isNull);
      expect(await dao.readPage(ownerId: 1, sessionUnitId: 'unit'), isEmpty);
    },
  );

  test('Controller does not replace a missing watermark with cached maximum', () async {
    final database = UnifiedDatabase(DatabaseConnection(NativeDatabase.memory()));
    addTearDown(database.close);
    final dao = MessageDao(database);
    await dao.upsertAll([ChatMessage.fromJson({'id': 500}, ownerId: 1, sessionUnitId: 'unit')]);
    final client = _RecoveryClient();
    final repo = MessageRepository(api: MessageApi(client), dao: dao);
    addTearDown(repo.dispose);
    final bus = SessionChangeBus();
    addTearDown(bus.dispose);
    final controller = ChatController(repo, _Sessions(),
      filePickerService: _Files(), attachmentTransferService: _Transfer(),
      mediaService: _Media(), audioPlaybackService: _Audio(), sessionChangeBus: bus,
      clipboardService: _Clipboard(), chatSettingsRepository: _Settings(),
      aiStreamChangeBus: AiStreamChangeBus(), signalRGateway: _Gateway(),
      ownerId: 1, sessionUnitId: 'unit', initialTitle: 'cached');
    addTearDown(controller.dispose);
    await controller.loadLatest();
    expect(client.cursors.first, 0);
    expect(await dao.findByServerId(ownerId: 1, sessionUnitId: 'unit', serverId: 1), isNotNull);
  });

  test(
    'known owners cannot read or delete legacy owner-zero or other-owner messages',
    () async {
      final database = UnifiedDatabase(
        DatabaseConnection(NativeDatabase.memory()),
      );
      addTearDown(database.close);
      final dao = MessageDao(database);
      await dao.upsertAll([
        for (final owner in [0, 1, 2])
          ChatMessage.fromJson(
            {'id': owner + 1},
            ownerId: owner,
            sessionUnitId: 'unit',
          ),
      ]);
      expect(
        (await dao.readPage(
          ownerId: 1,
          sessionUnitId: 'unit',
        )).map((m) => m.serverId),
        [2],
      );
      await database.deleteMessagesBySessionUnit(1, 'unit');
      expect(
        (await dao.readPage(
          ownerId: 0,
          sessionUnitId: 'unit',
        )).map((m) => m.serverId),
        [1],
      );
      expect(
        (await dao.readPage(
          ownerId: 2,
          sessionUnitId: 'unit',
        )).map((m) => m.serverId),
        [3],
      );
    },
  );

  test(
    'loadLatest with refreshRecent does not create a middle gap when latest hasMore, and background continuation publishes SessionChangeBus',
    () async {
      final database = UnifiedDatabase(
        DatabaseConnection(NativeDatabase.memory()),
      );
      addTearDown(database.close);
      final dao = MessageDao(database);
      await dao.upsertAll([
        ChatMessage.fromJson({'id': 10}, ownerId: 1, sessionUnitId: 'unit'),
      ]);
      await dao.writeMessageWatermark(1, 'unit', 10);
      final bus = SessionChangeBus();
      addTearDown(bus.dispose);
      final events = <SessionChangeEvent>[];
      final sub = bus.events.listen(events.add);
      addTearDown(sub.cancel);

      final client = _ContinuationGapClient();
      final repo = MessageRepository(
        api: MessageApi(client),
        dao: dao,
        sessionChangeBus: bus,
      );
      addTearDown(repo.dispose);

      // maxPages=1, limit=2 -> first call gets 11..12 with hasMore=true,
      // must NOT persist recent [99, 100] yet, and schedules continuation for 13..14.
      final first = await repo.loadLatest(
        ownerId: 1,
        sessionUnitId: 'unit',
        minMessageId: 10,
        limit: 2,
        maxPages: 1,
        refreshRecent: true,
      );
      expect(first.map((m) => m.serverId).toList()..sort(), [11, 12]);
      expect(
        await dao.findByServerId(ownerId: 1, sessionUnitId: 'unit', serverId: 100),
        isNull,
      );

      // Wait for scheduled continuation to fetch 13..14 and publish to SessionChangeBus
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(
        await dao.findByServerId(ownerId: 1, sessionUnitId: 'unit', serverId: 14),
        isNotNull,
      );
      expect(
        events.any(
          (e) =>
              e.ownerId == 1 &&
              e.sessionUnitId == 'unit' &&
              (e.messageIds?.contains(14) ?? false),
        ),
        isTrue,
      );
    },
  );

  test(
    'loadHistory with beforeScore on network failure does not return uncovered local messages past a gap',
    () async {
      final database = UnifiedDatabase(
        DatabaseConnection(NativeDatabase.memory()),
      );
      addTearDown(database.close);
      final dao = MessageDao(database);
      final m10 = ChatMessage.fromJson({'id': 10}, ownerId: 1, sessionUnitId: 'unit');
      final m100 = ChatMessage.fromJson({'id': 100}, ownerId: 1, sessionUnitId: 'unit');
      await dao.upsertAll([m10, m100]);

      final repo = MessageRepository(
        api: MessageApi(_FailingHistoryClient()),
        dao: dao,
      );
      addTearDown(repo.dispose);

      final page = await repo.loadHistory(
        ownerId: 1,
        sessionUnitId: 'unit',
        beforeScore: m100.score,
        limit: 10,
      );
      expect(page.items, isEmpty);
      expect(page.hasMore, isTrue);
    },
  );

  test(
    'ChatController.loadMore keeps hasMore=true on retryable empty page and recovers on retry',
    () async {
      final database = UnifiedDatabase(
        DatabaseConnection(NativeDatabase.memory()),
      );
      addTearDown(database.close);
      final dao = MessageDao(database);
      final m10 = ChatMessage.fromJson({'id': 10}, ownerId: 1, sessionUnitId: 'unit');
      final m100 = ChatMessage.fromJson({'id': 100}, ownerId: 1, sessionUnitId: 'unit');
      await dao.upsertAll([m10, m100]);

      final client = _ToggleFailHistoryClient();
      final repo = MessageRepository(
        api: MessageApi(client),
        dao: dao,
      );
      addTearDown(repo.dispose);

      final bus = SessionChangeBus();
      addTearDown(bus.dispose);
      final aiBus = AiStreamChangeBus();
      addTearDown(aiBus.dispose);
      final controller = ChatController(
        repo,
        _Sessions(),
        filePickerService: _Files(),
        attachmentTransferService: _Transfer(),
        mediaService: _Media(),
        audioPlaybackService: _Audio(),
        sessionChangeBus: bus,
        clipboardService: _Clipboard(),
        chatSettingsRepository: _Settings(),
        aiStreamChangeBus: aiBus,
        signalRGateway: _Gateway(),
        ownerId: 1,
        sessionUnitId: 'unit',
        initialTitle: 'cached',
      );
      addTearDown(controller.dispose);

      await controller.initialize();
      client.shouldFailHistory = true;
      await controller.loadMore();
      expect(controller.hasMore, isTrue);

      client.shouldFailHistory = false;
      await controller.loadMore();
      expect(controller.messages.any((m) => m.serverId == 5), isTrue);
    },
  );

  test(
    'loadNewerMessages on network failure does not skip uncovered gap or set hasMore=false',
    () async {
      final database = UnifiedDatabase(
        DatabaseConnection(NativeDatabase.memory()),
      );
      addTearDown(database.close);
      final dao = MessageDao(database);
      final m10 = ChatMessage.fromJson({'id': 10}, ownerId: 1, sessionUnitId: 'unit');
      final m100 = ChatMessage.fromJson({'id': 100}, ownerId: 1, sessionUnitId: 'unit');
      await dao.upsertAll([m10, m100]);

      final repo = MessageRepository(
        api: MessageApi(_FailingHistoryClient()),
        dao: dao,
      );
      addTearDown(repo.dispose);

      final page = await repo.loadNewerMessages(
        ownerId: 1,
        sessionUnitId: 'unit',
        afterScore: m10.score,
        afterServerId: 10,
        limit: 10,
      );
      expect(page.items, isEmpty);
      expect(page.hasMore, isTrue);
    },
  );

  test(
    'background continuation preserves refreshRecent=true on final caught-up round',
    () async {
      final database = UnifiedDatabase(
        DatabaseConnection(NativeDatabase.memory()),
      );
      addTearDown(database.close);
      final dao = MessageDao(database);
      await dao.upsertAll([
        ChatMessage.fromJson({'id': 10}, ownerId: 1, sessionUnitId: 'unit'),
      ]);
      await dao.writeMessageWatermark(1, 'unit', 10);

      final client = _RefreshRecentContinuationClient();
      final repo = MessageRepository(
        api: MessageApi(client),
        dao: dao,
      );
      addTearDown(repo.dispose);

      await repo.loadLatest(
        ownerId: 1,
        sessionUnitId: 'unit',
        minMessageId: 10,
        limit: 2,
        maxPages: 1,
        refreshRecent: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(client.historyCallCount, greaterThanOrEqualTo(1));
    },
  );

  test(
    'loadLatest with refreshRecent does not persist recent snapshot items above forwardWatermark',
    () async {
      final database = UnifiedDatabase(
        DatabaseConnection(NativeDatabase.memory()),
      );
      addTearDown(database.close);
      final dao = MessageDao(database);
      await dao.upsertAll([
        ChatMessage.fromJson({'id': 10}, ownerId: 1, sessionUnitId: 'unit'),
      ]);
      await dao.writeMessageWatermark(1, 'unit', 10);

      final repo = MessageRepository(
        api: MessageApi(_RecentAboveWatermarkClient()),
        dao: dao,
      );
      addTearDown(repo.dispose);

      await repo.loadLatest(
        ownerId: 1,
        sessionUnitId: 'unit',
        minMessageId: 10,
        limit: 10,
        maxPages: 1,
        refreshRecent: true,
      );
      expect(
        await dao.findByServerId(ownerId: 1, sessionUnitId: 'unit', serverId: 11),
        isNotNull,
      );
      expect(
        await dao.findByServerId(ownerId: 1, sessionUnitId: 'unit', serverId: 999),
        isNull,
      );
    },
  );

  test(
    'loadLatest with minMessageId 0 and existing cache skips recent snapshot while hasMore and enforces forwardWatermark when caught up',
    () async {
      final database = UnifiedDatabase(
        DatabaseConnection(NativeDatabase.memory()),
      );
      addTearDown(database.close);
      final dao = MessageDao(database);
      await dao.upsertAll([
        ChatMessage.fromJson({'id': 5}, ownerId: 1, sessionUnitId: 'unit'),
      ]);

      final hasMoreClient = _ZeroCursorNonEmptyClient(hasMore: true);
      final repo1 = MessageRepository(
        api: MessageApi(hasMoreClient),
        dao: dao,
      );
      addTearDown(repo1.dispose);

      await repo1.loadLatest(
        ownerId: 1,
        sessionUnitId: 'unit',
        minMessageId: 0,
        limit: 10,
        maxPages: 1,
        refreshRecent: true,
      );
      expect(hasMoreClient.historyCalls, 0);
      expect(
        await dao.findByServerId(ownerId: 1, sessionUnitId: 'unit', serverId: 999),
        isNull,
      );

      final caughtUpClient = _ZeroCursorNonEmptyClient(hasMore: false);
      final repo2 = MessageRepository(
        api: MessageApi(caughtUpClient),
        dao: dao,
      );
      addTearDown(repo2.dispose);

      await repo2.loadLatest(
        ownerId: 1,
        sessionUnitId: 'unit',
        minMessageId: 0,
        limit: 10,
        maxPages: 1,
        refreshRecent: true,
      );
      expect(caughtUpClient.historyCalls, 1);
      expect(
        await dao.findByServerId(ownerId: 1, sessionUnitId: 'unit', serverId: 11),
        isNotNull,
      );
      expect(
        await dao.findByServerId(ownerId: 1, sessionUnitId: 'unit', serverId: 999),
        isNull,
      );
    },
  );
}

class _ZeroCursorNonEmptyClient implements ApiClient {
  _ZeroCursorNonEmptyClient({required this.hasMore});

  final bool hasMore;
  int historyCalls = 0;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    bool retryOnUnauthorized = true,
  }) async {
    if (path.endsWith('/message/latest')) {
      return {
        'items': [
          {'id': 11, 'sessionUnitId': 'unit', 'content': {'text': 'm11'}},
        ],
        'extra': {'hasMore': hasMore},
      } as T;
    }
    if (path.endsWith('/message/history')) {
      historyCalls += 1;
      return {
        'items': [
          {'id': 999, 'sessionUnitId': 'unit', 'content': {'text': 'future 999'}},
          {'id': 11, 'sessionUnitId': 'unit', 'content': {'text': 'm11'}},
        ],
        'extra': {'hasMore': false},
      } as T;
    }
    return {'items': [], 'totalCount': 0} as T;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecentAboveWatermarkClient implements ApiClient {
  @override
  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    bool retryOnUnauthorized = true,
  }) async {
    if (path.endsWith('/message/latest')) {
      return {
        'items': [
          {'id': 11, 'sessionUnitId': 'unit', 'content': {'text': 'm11'}},
        ],
        'extra': {'hasMore': false},
      } as T;
    }
    if (path.endsWith('/message/history')) {
      return {
        'items': [
          {'id': 999, 'sessionUnitId': 'unit', 'content': {'text': 'future 999'}},
          {'id': 11, 'sessionUnitId': 'unit', 'content': {'text': 'm11'}},
        ],
        'extra': {'hasMore': false},
      } as T;
    }
    return {'items': [], 'totalCount': 0} as T;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ToggleFailHistoryClient implements ApiClient {
  bool shouldFailHistory = false;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    bool retryOnUnauthorized = true,
  }) async {
    if (path.endsWith('/message/history')) {
      if (shouldFailHistory) {
        throw const ApiException('offline', statusCode: 503);
      }
      return {
        'items': [
          {'id': 5, 'sessionUnitId': 'unit', 'content': {'text': 'recovered 5'}},
        ],
        'extra': {'hasMore': true},
      } as T;
    }
    return {'items': [], 'extra': {'hasMore': false}} as T;
  }

  @override
  Future<T> post<T>(
    String path, {
    Map<String, Object?>? query,
    Object? data,
    Map<String, String>? headers,
    bool retryOnUnauthorized = true,
  }) async {
    if (path.endsWith('/message-change/pull')) {
      return {
        'epoch': 'epoch-1',
        'headChangeId': '0',
        'nextCursor': '0',
        'items': [],
      } as T;
    }
    return <String, Object?>{} as T;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RefreshRecentContinuationClient implements ApiClient {
  int historyCallCount = 0;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    bool retryOnUnauthorized = true,
  }) async {
    if (path.endsWith('/message/history')) {
      historyCallCount++;
      return {
        'items': [
          {'id': 14, 'sessionUnitId': 'unit', 'content': {'text': 'm14'}},
          {'id': 13, 'sessionUnitId': 'unit', 'content': {'text': 'm13'}},
        ],
        'extra': {'hasMore': false},
      } as T;
    }
    if (path.endsWith('/message/latest')) {
      final minId = (query?['minMessageId'] as num?)?.toInt() ?? 0;
      if (minId == 10) {
        return {
          'items': [
            {'id': 11, 'sessionUnitId': 'unit', 'content': {'text': 'm11'}},
            {'id': 12, 'sessionUnitId': 'unit', 'content': {'text': 'm12'}},
          ],
          'extra': {'hasMore': true},
        } as T;
      }
      if (minId == 12) {
        return {
          'items': [
            {'id': 13, 'sessionUnitId': 'unit', 'content': {'text': 'm13'}},
            {'id': 14, 'sessionUnitId': 'unit', 'content': {'text': 'm14'}},
          ],
          'extra': {'hasMore': false},
        } as T;
      }
      return {'items': [], 'extra': {'hasMore': false}} as T;
    }
    return {'items': [], 'totalCount': 0} as T;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingHistoryClient implements ApiClient {
  @override
  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    bool retryOnUnauthorized = true,
  }) async {
    throw const ApiException('offline', statusCode: 503);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ContinuationGapClient implements ApiClient {
  @override
  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    bool retryOnUnauthorized = true,
  }) async {
    if (path.endsWith('/message/history')) {
      return {
        'items': [
          {'id': 100, 'sessionUnitId': 'unit', 'content': {'text': 'newest 100'}},
          {'id': 99, 'sessionUnitId': 'unit', 'content': {'text': 'newest 99'}},
        ],
        'extra': {'hasMore': true},
      } as T;
    }
    if (path.endsWith('/message/latest')) {
      final minId = (query?['minMessageId'] as num?)?.toInt() ?? 0;
      if (minId == 10) {
        return {
          'items': [
            {'id': 11, 'sessionUnitId': 'unit', 'content': {'text': 'm11'}},
            {'id': 12, 'sessionUnitId': 'unit', 'content': {'text': 'm12'}},
          ],
          'extra': {'hasMore': true},
        } as T;
      }
      if (minId == 12) {
        return {
          'items': [
            {'id': 13, 'sessionUnitId': 'unit', 'content': {'text': 'm13'}},
            {'id': 14, 'sessionUnitId': 'unit', 'content': {'text': 'm14'}},
          ],
          'extra': {'hasMore': false},
        } as T;
      }
      return {'items': [], 'extra': {'hasMore': false}} as T;
    }
    return {'items': [], 'totalCount': 0} as T;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
