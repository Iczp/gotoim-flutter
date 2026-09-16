import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/realtime/signalr_gateway.dart';
import 'package:gotoim_flutter/features/session/application/presence_heartbeat_coordinator.dart';

void main() {
  test('sends immediately on connect and restarts after reconnect', () async {
    final gateway = _FakeSignalRGateway();
    final coordinator = PresenceHeartbeatCoordinator(
      gateway: gateway,
      interval: const Duration(minutes: 1),
    );
    coordinator.start();

    gateway.emit(SignalRConnectionState.connected);
    await Future<void>.delayed(Duration.zero);
    expect(gateway.invokedMethods, <String>['Heartbeat']);

    gateway.emit(SignalRConnectionState.reconnecting);
    gateway.emit(SignalRConnectionState.connected);
    await Future<void>.delayed(Duration.zero);
    expect(gateway.invokedMethods, <String>['Heartbeat', 'Heartbeat']);

    await coordinator.dispose();
    await gateway.dispose();
  });
}

class _FakeSignalRGateway implements SignalRGateway {
  final StreamController<SignalRAppEvent> _events =
      StreamController<SignalRAppEvent>.broadcast();
  final List<String> invokedMethods = <String>[];
  SignalRConnectionState _state = SignalRConnectionState.disconnected;

  @override
  Stream<SignalRAppEvent> get events => _events.stream;

  @override
  SignalRConnectionState get connectionState => _state;

  @override
  SignalRConnectionInfo get connectionInfo => SignalRConnectionInfo(
    hubUrl: 'http://test/signalr-hubs/chat',
    state: _state,
    connectionId: 'test-connection',
    keepAliveInterval: const Duration(seconds: 15),
    serverTimeout: const Duration(seconds: 30),
  );

  void emit(SignalRConnectionState state) {
    _state = state;
    _events.add(
      SignalRConnectionEvent(state: state, receivedAt: DateTime.now()),
    );
  }

  @override
  Future<void> connect() async => emit(SignalRConnectionState.connected);

  @override
  Future<void> disconnect() async => emit(SignalRConnectionState.disconnected);

  @override
  Future<T?> invoke<T>(String method, {List<Object>? arguments}) async {
    invokedMethods.add(method);
    return null;
  }

  @override
  Future<void> dispose() => _events.close();
}
