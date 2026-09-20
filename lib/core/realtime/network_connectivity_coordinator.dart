import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/application_providers.dart';
import '../capabilities/client_capability_models.dart';
import '../capabilities/client_capability_service.dart';
import '../logging/app_logger.dart';
import '../network/token_storage.dart';
import '../../features/auth/application/auth_controller.dart';
import 'signalr_gateway.dart';

/// Monitors system network transitions and app lifecycle to guarantee
/// instant SignalR reconnection without waiting for stale TCP sockets to time out.
class NetworkConnectivityCoordinator {
  NetworkConnectivityCoordinator({
    required SignalRGateway gateway,
    required TokenStorage tokenStorage,
    required ClientCapabilityService capabilities,
  })  : _gateway = gateway,
        _tokenStorage = tokenStorage,
        _capabilities = capabilities;

  final SignalRGateway _gateway;
  final TokenStorage _tokenStorage;
  final ClientCapabilityService _capabilities;

  StreamSubscription<ClientNetworkStatus>? _subscription;
  ClientNetworkStatus? _lastStatus;
  bool _isStarted = false;

  void start() {
    if (_isStarted) return;
    _isStarted = true;

    _subscription = _capabilities.networkStatusChanges.listen(_onNetworkChanged);
  }

  Future<void> _onNetworkChanged(ClientNetworkStatus status) async {
    final previous = _lastStatus;
    _lastStatus = status;

    if (previous == null) return;

    final wasConnected = previous.isConnected;
    final isConnected = status.isConnected;
    final networkTypeChanged = !setEquals(
      previous.types.toSet(),
      status.types.toSet(),
    );

    AppLogger.instance.info(
      'Network changed: ${previous.types} -> ${status.types} (connected: $isConnected)',
      category: 'network',
      event: 'connectivity_changed',
      context: <String, Object?>{
        'previous': previous.types.map((t) => t.name).toList(),
        'current': status.types.map((t) => t.name).toList(),
        'isConnected': isConnected,
      },
    );

    if (!isConnected) {
      AppLogger.instance.info(
        'Network disconnected, waiting for reconnection',
        category: 'signalr',
        event: 'network_lost',
      );
      return;
    }

    // If network reconnected from offline OR switched interface (e.g. WiFi <-> Mobile)
    if (!wasConnected || networkTypeChanged) {
      final hasToken = await _tokenStorage.hasToken();
      if (!hasToken) return;

      AppLogger.instance.info(
        'Network switch/restoration detected, initiating fast SignalR restart',
        category: 'signalr',
        event: 'fast_reconnect_triggered',
      );

      try {
        await _gateway.restart(fast: true);
      } catch (e) {
        AppLogger.instance.error(
          'SignalR fast restart failed after network transition',
          category: 'signalr',
          event: 'fast_reconnect_failed',
          error: e,
        );
      }
    }
  }

  Future<void> handleAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      final hasToken = await _tokenStorage.hasToken();
      if (!hasToken) return;

      if (_gateway.connectionState == SignalRConnectionState.disconnected) {
        AppLogger.instance.info(
          'App resumed with disconnected SignalR, attempting connection',
          category: 'signalr',
          event: 'resume_connect',
        );
        try {
          await _gateway.connect();
        } catch (_) {}
      }
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _isStarted = false;
  }
}

final networkConnectivityCoordinatorProvider =
    Provider<NetworkConnectivityCoordinator>((ref) {
  final coordinator = NetworkConnectivityCoordinator(
    gateway: ref.watch(signalRGatewayProvider),
    tokenStorage: ref.watch(tokenStorageProvider),
    capabilities: ref.watch(clientCapabilityServiceProvider),
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});
