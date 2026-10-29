import 'dart:async';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/database/unified_database.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';
import 'package:gotoim_flutter/core/realtime/signalr_gateway.dart';
import 'package:gotoim_flutter/features/chat/application/ai_stream_change_bus.dart';
import 'package:gotoim_flutter/features/chat/data/datasources/message_api.dart';
import 'package:gotoim_flutter/features/chat/data/datasources/message_dao.dart';
import 'package:gotoim_flutter/features/chat/data/models/chat_message.dart';
import 'package:gotoim_flutter/features/chat/data/repositories/message_repository.dart';
import 'package:gotoim_flutter/features/session/application/active_chat_registry.dart';
import 'package:gotoim_flutter/features/session/application/message_alert_coordinator.dart';
import 'package:gotoim_flutter/features/session/application/realtime_sync_coordinator.dart';
import 'package:gotoim_flutter/features/session/data/models/session_summary.dart';
import 'package:gotoim_flutter/features/session/data/repositories/session_repository.dart';

class _Gateway extends Fake implements SignalRGateway {
  final controller = StreamController<SignalRAppEvent>.broadcast(sync: true);
  @override
  Stream<SignalRAppEvent> get events => controller.stream;
}

class _Sessions extends Fake implements SessionRepository {
  int syncs = 0;
  @override
  Future<int?> readCurrentOwnerId() async => 1;
  @override
  Future<List<SessionSummary>> loadChanges({required int ownerId}) async {
    syncs++;
    return [];
  }
}

class _Client extends Fake implements ApiClient {
  int calls = 0;
  @override
  Future<T> post<T>(
    String path, {
    Map<String, Object?>? query,
    Object? data,
    Map<String, String>? headers,
    bool retryOnUnauthorized = true,
  }) async {
    calls++;
    final sessions = (data as Map)['sessions'] as List;
    return sessions
            .map(
              (s) => {
                'sessionUnitId': s['sessionUnitId'],
                'nextCursor': 'next',
                'items': [],
                'hasMore': false,
              },
            )
            .toList()
        as T;
  }
}

class _Alerts extends Fake implements MessageAlertCoordinator {}

void main() {
  test('badge events skip message scans; reconnect still catches up', () async {
    final db = UnifiedDatabase(DatabaseConnection(NativeDatabase.memory()));
    await db.initialize();
    final dao = MessageDao(db);
    await dao.upsertAll([
      ChatMessage.fromJson({'id': 1}, ownerId: 1, sessionUnitId: 'unit'),
    ]);
    final client = _Client();
    final gateway = _Gateway();
    final sessions = _Sessions();
    final coordinator = RealtimeSyncCoordinator(
      gateway: gateway,
      sessionRepository: sessions,
      messageRepository: MessageRepository(api: MessageApi(client), dao: dao),
      aiStreamChangeBus: AiStreamChangeBus(),
      messageAlertCoordinator: _Alerts(),
      activeChatRegistry: ActiveChatRegistry(),
      onKicked: (_) async {},
    );
    coordinator.start();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(client.calls, 1);
    gateway.controller.add(
      SignalRCommandEvent(
        command: SignalRCommand.messageBadgeUpdated,
        envelope: {
          'payload': {'ownerId': 1},
        },
        receivedAt: DateTime.now(),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(client.calls, 1);
    expect(sessions.syncs, greaterThanOrEqualTo(2));
    gateway.controller.add(
      SignalRConnectionEvent(
        state: SignalRConnectionState.connected,
        receivedAt: DateTime.now(),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(client.calls, 2);
    await coordinator.dispose();
    await gateway.controller.close();
    await db.close();
  });
}
