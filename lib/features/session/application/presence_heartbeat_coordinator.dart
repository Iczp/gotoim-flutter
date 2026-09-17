import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/realtime/signalr_gateway.dart';
import '../../auth/application/auth_controller.dart';

/// Refreshes the server-side IM presence record while SignalR is connected.
///
/// SignalR transport keep-alives only prove that a socket is open. The ChatHub
/// `Heartbeat` method separately extends the Redis connection/device/session
/// indexes used for online state and message delivery. This coordinator keeps
/// running in the background as requested; mobile OS suspension can still
/// delay Dart timers, and the next successful connection always sends an
/// immediate catch-up heartbeat.
class PresenceHeartbeatCoordinator {
  PresenceHeartbeatCoordinator({
    required SignalRGateway gateway,
    required Duration interval,
  }) : _gateway = gateway,
       _interval = interval;

  final SignalRGateway _gateway;
  final Duration _interval;
  StreamSubscription<SignalRAppEvent>? _subscription;
  Timer? _timer;
  bool _sending = false;
  bool _started = false;
  int _consecutiveFailures = 0;

  void start() {
    if (_started) return;
    _started = true;
    _subscription = _gateway.events.listen(_onSignalREvent);
    if (_gateway.connectionState == SignalRConnectionState.connected) {
      _startConnectedHeartbeat();
    }
  }

  void _onSignalREvent(SignalRAppEvent event) {
    if (event is! SignalRConnectionEvent) return;
    if (event.state == SignalRConnectionState.connected) {
      _startConnectedHeartbeat();
    } else {
      _consecutiveFailures = 0;
      _stopTimer();
    }
  }

  void _startConnectedHeartbeat() {
    _consecutiveFailures = 0;
    _stopTimer();
    unawaited(_sendHeartbeat());
    _timer = Timer.periodic(_interval, (_) => unawaited(_sendHeartbeat()));
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _sendHeartbeat() async {
    if (_sending ||
        _gateway.connectionState != SignalRConnectionState.connected) {
      return;
    }
    _sending = true;
    final ticks = DateTime.now().millisecondsSinceEpoch;
    try {
      await _gateway.invoke<Object>('Heartbeat', arguments: [ticks]);
      _consecutiveFailures = 0;
      AppLogger.instance.info(
        'Presence heartbeat sent',
        category: 'presence',
        event: 'heartbeat_sent',
        context: <String, Object?>{'ticks': ticks},
      );
    } catch (error, stackTrace) {
      _consecutiveFailures++;
      AppLogger.instance.error(
        'Presence heartbeat failed (count: $_consecutiveFailures)',
        category: 'presence',
        event: 'heartbeat_failed',
        error: error,
        stackTrace: stackTrace,
      );
      debugPrint('[presenceHeartbeat] failed (count: $_consecutiveFailures): $error');
      if (_consecutiveFailures >= 2 &&
          _gateway.connectionState == SignalRConnectionState.connected) {
        AppLogger.instance.warning(
          'Consecutive presence heartbeats failed, disconnecting to trigger transport recovery',
          category: 'presence',
          event: 'heartbeat_recovery_disconnect',
        );
        unawaited(_gateway.disconnect());
      }
    } finally {
      _sending = false;
    }
  }

  Future<void> dispose() async {
    _stopTimer();
    await _subscription?.cancel();
  }
}

final presenceHeartbeatCoordinatorProvider =
    Provider<PresenceHeartbeatCoordinator>((ref) {
      final coordinator = PresenceHeartbeatCoordinator(
        gateway: ref.watch(signalRGatewayProvider),
        interval: ref.watch(appEnvironmentProvider).presenceHeartbeatInterval,
      );
      ref.onDispose(coordinator.dispose);
      return coordinator;
    });
