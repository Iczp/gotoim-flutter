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

class _Client implements ApiClient {
  final historyCalls = <Object?>[];
  Completer<Object>? delayedLatest;
  Completer<void>? latestStarted;
  bool failChanges = false;
  @override
  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    bool retryOnUnauthorized = true,
  }) async {
    if (path.endsWith('/history')) historyCalls.add(query);
    latestStarted?.complete();
    latestStarted = null;
    return (delayedLatest == null
            ? {'items': [], 'totalCount': 0}
            : await delayedLatest!.future)
        as T;
  }

  @override
  Future<T> post<T>(
    String path, {
    Map<String, Object?>? query,
    Object? data,
    Map<String, String>? headers,
    bool retryOnUnauthorized = true,
  }) async {
    if (path.endsWith('/sync-items')) return <Object>[] as T;
    if (path.endsWith('/changes/query')) {
      if (failChanges) throw StateError('sync temporarily unavailable');
      final scope = ((data as Map)['sessions'] as List).single as Map;
      return [
            {
              'sessionUnitId': 'unit',
              'nextCursor': 'cursor',
              'snapshotCursor': 'cursor',
              'resetRequired': scope['cursor'] == null,
              'hasMore': false,
              'items': [],
            },
          ]
          as T;
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
    'readMessageId': 100000,
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
    'cached chat entry uses the change journal and a late latest response cannot restore a deleted bubble',
    () async {
      final database = UnifiedDatabase(
        DatabaseConnection(NativeDatabase.memory()),
      );
      addTearDown(database.close);
      final dao = MessageDao(database);
      final original = ChatMessage.fromJson(
        {
          'id': 5,
          'content': {'text': 'cached'},
        },
        ownerId: 1,
        sessionUnitId: 'unit',
      );
      await dao.upsertAll([original]);
      final bus = SessionChangeBus();
      addTearDown(bus.dispose);
      final client = _Client()..latestStarted = Completer<void>();
      final started = client.latestStarted!.future;
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
        initialTitle: 'cached',
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await started.timeout(const Duration(seconds: 5));
      expect(client.historyCalls, isEmpty);
      expect(controller.messages.single.serverId, 5);
      client.delayedLatest = Completer<Object>();
      client.failChanges = true;
      client.latestStarted = Completer<void>();
      final nextStarted = client.latestStarted!.future;
      // Finish any initial asynchronous UI notification before this new pull.
      while (controller.isLoadingLatest) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      final late = controller.loadLatest(refreshRecent: true);
      await nextStarted;
      await repo.deleteRemote(original);
      client.delayedLatest!.complete({
        'items': [original.raw],
        'totalCount': 1,
      });
      await late;
      expect(controller.messages, isEmpty);
      expect(
        await dao.findByServerId(
          ownerId: 1,
          sessionUnitId: 'unit',
          serverId: 5,
        ),
        isNull,
      );
      expect(client.historyCalls, isEmpty);
    },
  );
}
