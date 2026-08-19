import 'dart:async';

import 'package:signalr_netcore/signalr_client.dart';

import '../config/app_environment.dart';
import '../device/client_device_context.dart';
import 'signalr_access_token_reader.dart';
import 'signalr_gateway.dart';

SignalRGateway createPlatformSignalRGateway({
  required AppEnvironment environment,
  required SignalRAccessTokenReader readAccessToken,
  required ClientDeviceContext deviceContext,
}) {
  return SignalRNetcoreGateway(
    environment: environment,
    readAccessToken: readAccessToken,
    deviceContext: deviceContext,
  );
}

class SignalRNetcoreGateway implements SignalRGateway {
  SignalRNetcoreGateway({
    required AppEnvironment environment,
    required SignalRAccessTokenReader readAccessToken,
    required ClientDeviceContext deviceContext,
  }) : _connection =
           HubConnectionBuilder()
               .withUrl(
                 _withDeviceQuery(environment.signalRHubUrl, deviceContext),
                 options: HttpConnectionOptions(
                   skipNegotiation: environment.signalRSkipNegotiation,
                   transport: HttpTransportType.WebSockets,
                   accessTokenFactory:
                       () async => await readAccessToken() ?? '',
                 ),
               )
               .withAutomaticReconnect(
                 retryDelays: environment.signalRReconnectDelays,
               )
               .build() {
    _connection.on('ReceivedMessage', _onReceivedMessage);
    _connection.onreconnecting(
      ({error}) =>
          _emitConnection(SignalRConnectionState.reconnecting, error: error),
    );
    _connection.onreconnected(
      ({connectionId}) => _emitConnection(
        SignalRConnectionState.connected,
        connectionId: connectionId,
      ),
    );
    _connection.onclose(
      ({error}) =>
          _emitConnection(SignalRConnectionState.disconnected, error: error),
    );
  }

  final HubConnection _connection;
  final StreamController<SignalRAppEvent> _events =
      StreamController<SignalRAppEvent>.broadcast();
  DateTime? _lastReceivedAt;

  @override
  SignalRConnectionState get connectionState => _mapState(_connection.state);

  @override
  SignalRConnectionInfo get connectionInfo => SignalRConnectionInfo(
    hubUrl: _connection.baseUrl ?? '',
    state: connectionState,
    connectionId: _connection.connectionId,
    keepAliveInterval: Duration(
      milliseconds: _connection.keepAliveIntervalInMilliseconds,
    ),
    serverTimeout: Duration(
      milliseconds: _connection.serverTimeoutInMilliseconds,
    ),
    lastReceivedAt: _lastReceivedAt,
  );

  @override
  Stream<SignalRAppEvent> get events => _events.stream;

  @override
  Future<void> connect() async {
    if (connectionState == SignalRConnectionState.connected ||
        connectionState == SignalRConnectionState.connecting ||
        connectionState == SignalRConnectionState.reconnecting) {
      return;
    }
    _emitConnection(SignalRConnectionState.connecting);
    try {
      await _connection.start();
      _emitConnection(SignalRConnectionState.connected);
    } catch (error) {
      _emitConnection(SignalRConnectionState.disconnected, error: error);
      rethrow;
    }
  }

  @override
  Future<void> disconnect() => _connection.stop();

  @override
  Future<void> dispose() async {
    await disconnect();
    await _events.close();
  }

  @override
  Future<T?> invoke<T>(String method, {List<Object>? arguments}) async {
    return await _connection.invoke(method, args: arguments) as T?;
  }

  void _onReceivedMessage(List<Object?>? arguments) {
    final value =
        arguments == null || arguments.isEmpty ? null : arguments.first;
    final envelope = _asMap(value);
    final commandValue = envelope?['command']?.toString();
    final now = DateTime.now();
    _lastReceivedAt = now;
    final command =
        commandValue == null ? null : SignalRCommand.fromValue(commandValue);
    if (envelope == null || command == null) {
      _events.add(
        SignalRUnknownCommandEvent(
          command: commandValue,
          envelope: envelope ?? const <String, dynamic>{},
          receivedAt: now,
        ),
      );
      return;
    }
    _events.add(
      SignalRCommandEvent(
        command: command,
        envelope: envelope,
        receivedAt: now,
      ),
    );
  }

  Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  void _emitConnection(
    SignalRConnectionState state, {
    Object? error,
    String? connectionId,
  }) {
    if (!_events.isClosed) {
      _events.add(
        SignalRConnectionEvent(
          state: state,
          error: error,
          connectionId: connectionId,
          receivedAt: DateTime.now(),
        ),
      );
    }
  }

  SignalRConnectionState _mapState(HubConnectionState? state) {
    switch (state) {
      case HubConnectionState.Connecting:
        return SignalRConnectionState.connecting;
      case HubConnectionState.Connected:
        return SignalRConnectionState.connected;
      case HubConnectionState.Reconnecting:
        return SignalRConnectionState.reconnecting;
      case HubConnectionState.Disconnecting:
        return SignalRConnectionState.disconnecting;
      case HubConnectionState.Disconnected:
      case null:
        return SignalRConnectionState.disconnected;
    }
  }

  static String _withDeviceQuery(
    String hubUrl,
    ClientDeviceContext deviceContext,
  ) {
    final uri = Uri.parse(hubUrl);
    return uri
        .replace(
          queryParameters: <String, String>{
            ...uri.queryParameters,
            ...deviceContext.signalRQueryParameters,
          },
        )
        .toString();
  }
}
