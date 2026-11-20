import 'dart:async';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/database/unified_database.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';
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
}
