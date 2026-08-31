import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/realtime/signalr_gateway.dart';
import '../../auth/application/auth_controller.dart';
import '../../chat/application/chat_controller.dart';
import '../../chat/data/repositories/message_repository.dart';
import 'session_list_controller.dart';
import '../data/repositories/session_repository.dart';

/// The sole application-level consumer that turns realtime notifications into
/// persisted IM state. Pages observe repository change buses instead of the
/// SignalR transport, so a closed chat cannot miss an incoming message.
class RealtimeSyncCoordinator {
  RealtimeSyncCoordinator({
    required SignalRGateway gateway,
    required SessionRepository sessionRepository,
    required MessageRepository messageRepository,
  }) : _gateway = gateway,
       _sessionRepository = sessionRepository,
       _messageRepository = messageRepository;

  final SignalRGateway _gateway;
  final SessionRepository _sessionRepository;
  final MessageRepository _messageRepository;
  StreamSubscription<SignalRAppEvent>? _subscription;
  Timer? _syncTimer;
  Future<void>? _syncInFlight;

  void start() {
    _subscription ??= _gateway.events.listen(_onEvent);
  }

  void _onEvent(SignalRAppEvent event) {
    if (event is SignalRConnectionEvent &&
        event.state == SignalRConnectionState.connected) {
      _scheduleOwnerSync();
      return;
    }
    if (event is! SignalRCommandEvent) return;
    switch (event.command) {
      case SignalRCommand.messageCreated:
      case SignalRCommand.messageForwarded:
      case SignalRCommand.messageUpdated:
      case SignalRCommand.messageRollbacked:
        unawaited(_persistMessage(event));
        _scheduleOwnerSync();
        break;
      case SignalRCommand.messageBadgeUpdated:
      case SignalRCommand.sessionUnitChanged:
        _scheduleOwnerSync();
        break;
      default:
        break;
    }
  }

  Future<void> _persistMessage(SignalRCommandEvent event) async {
    try {
      await _messageRepository.applyRealtimePayloadFromCachedSession(
        event.payload,
      );
    } catch (error) {
      debugPrint('[realtimeSync][message-failed] error=$error');
    }
  }

  void _scheduleOwnerSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(milliseconds: 250), () {
      unawaited(_syncCachedOwners());
    });
  }

  Future<void> _syncCachedOwners() {
    final existing = _syncInFlight;
    if (existing != null) return existing;
    final sync = _syncOwners();
    _syncInFlight = sync;
    return sync.whenComplete(() {
      if (identical(_syncInFlight, sync)) _syncInFlight = null;
    });
  }

  Future<void> _syncOwners() async {
    final owners = await _sessionRepository.loadLocalOwners();
    for (final owner in owners) {
      try {
        await _sessionRepository.loadChanges(ownerId: owner.id);
      } catch (error) {
        // Realtime is advisory. Retain local state and let the next command or
        // foreground refresh retry the incremental request.
        debugPrint(
          '[realtimeSync][changes-failed] owner=${owner.id} error=$error',
        );
      }
    }
  }

  Future<void> dispose() async {
    _syncTimer?.cancel();
    await _subscription?.cancel();
  }
}

final realtimeSyncCoordinatorProvider = Provider<RealtimeSyncCoordinator>((
  ref,
) {
  final coordinator = RealtimeSyncCoordinator(
    gateway: ref.watch(signalRGatewayProvider),
    sessionRepository: ref.watch(sessionRepositoryProvider),
    messageRepository: ref.watch(messageRepositoryProvider),
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});
