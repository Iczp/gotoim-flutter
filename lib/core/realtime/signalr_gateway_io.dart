import 'dart:async';

import 'package:signalr_netcore/signalr_client.dart';

import '../config/app_environment.dart';
import '../device/client_device_context.dart';
import '../logging/app_logger.dart';
import '../network/jwt_token_expiry.dart';
import '../network/token_refresher.dart';
import 'signalr_access_token_reader.dart';
import 'signalr_gateway.dart';

SignalRGateway createPlatformSignalRGateway({
  required AppEnvironment environment,
  required SignalRAccessTokenReader readAccessToken,
  required ClientDeviceContext deviceContext,
  Future<String?> Function()? refreshToken,
  FutureOr<void> Function()? onSessionInvalidated,
}) {
  return SignalRNetcoreGateway(
    environment: environment,
    readAccessToken: readAccessToken,
    deviceContext: deviceContext,
    refreshToken: refreshToken,
    onSessionInvalidated: onSessionInvalidated,
  );
}

class SignalRNetcoreGateway implements SignalRGateway {
  SignalRNetcoreGateway({
    required AppEnvironment environment,
    required SignalRAccessTokenReader readAccessToken,
    required ClientDeviceContext deviceContext,
    Future<String?> Function()? refreshToken,
    FutureOr<void> Function()? onSessionInvalidated,
  })  : _environment = environment,
        _readAccessToken = readAccessToken,
        _deviceContext = deviceContext,
        _refreshToken = refreshToken,
        _onSessionInvalidated = onSessionInvalidated {
    _initConnection();
  }

  final AppEnvironment _environment;
  final SignalRAccessTokenReader _readAccessToken;
  final ClientDeviceContext _deviceContext;
  final Future<String?> Function()? _refreshToken;
  final FutureOr<void> Function()? _onSessionInvalidated;

  HubConnection? _connection;
  final StreamController<SignalRAppEvent> _events =
      StreamController<SignalRAppEvent>.broadcast();
  DateTime? _lastReceivedAt;
  Object? _lastError;
  String? _lastErrorDescription;
  bool _isConnectingOrRestarting = false;

  void _initConnection() {
    final conn = HubConnectionBuilder()
        .withUrl(
          _withDeviceQuery(_environment.signalRHubUrl, _deviceContext),
          options: HttpConnectionOptions(
            skipNegotiation: _environment.signalRSkipNegotiation,
            transport: HttpTransportType.WebSockets,
            accessTokenFactory: () async {
              var token = await _readAccessToken();
              if (token != null &&
                  token.isNotEmpty &&
                  shouldRefreshJwt(token)) {
                AppLogger.instance.info(
                  'SignalR proactive token refresh before connect/reconnect',
                  category: 'signalr',
                  event: 'proactive_token_refresh',
                );
                try {
                  final refresh = _refreshToken;
                  if (refresh != null) {
                    final refreshed = await refresh();
                    if (refreshed != null && refreshed.isNotEmpty) {
                      token = refreshed;
                    }
                  }
                } catch (e) {
                  AppLogger.instance.error(
                    'SignalR proactive token refresh failed',
                    category: 'signalr',
                    event: 'proactive_token_refresh_failed',
                    error: e,
                  );
                }
              }
              return token ?? '';
            },
          ),
        )
        .withAutomaticReconnect(
          retryDelays: _environment.signalRReconnectDelays,
        )
        .build();

    conn.keepAliveIntervalInMilliseconds = 5000;
    conn.serverTimeoutInMilliseconds = 15000;

    conn.on('ReceivedMessage', _onReceivedMessage);
    conn.onreconnecting(
      ({error}) =>
          _emitConnection(SignalRConnectionState.reconnecting, error: error),
    );
    conn.onreconnected(
      ({connectionId}) => _emitConnection(
        SignalRConnectionState.connected,
        connectionId: connectionId,
      ),
    );
    conn.onclose(
      ({error}) async {
        _emitConnection(SignalRConnectionState.disconnected, error: error);
        final refresh = _refreshToken;
        if (_isUnauthorizedError(error) && refresh != null) {
          AppLogger.instance.info(
            'SignalR onclose error was 401 Unauthorized, refreshing token...',
            category: 'signalr',
            event: 'onclose_401_refresh',
          );
          try {
            final currentToken = await _readAccessToken();
            String? newToken = currentToken;
            if (currentToken == null || currentToken.isEmpty || shouldRefreshJwt(currentToken)) {
              newToken = await refresh();
            }
            if (newToken != null && newToken.isNotEmpty) {
              unawaited(restart(fast: true));
            }
          } catch (e) {
            AppLogger.instance.error(
              'SignalR onclose token refresh failed',
              category: 'signalr',
              error: e,
            );
          }
        }
      },
    );

    _connection = conn;
  }

  bool _isUnauthorizedError(Object? error) {
    if (error == null) return false;
    final msg = error.toString().toLowerCase();
    return msg.contains('401') ||
        msg.contains('unauthorized') ||
        msg.contains('status code: 401') ||
        msg.contains('status code 401');
  }

  @override
  SignalRConnectionState get connectionState =>
      _mapState(_connection?.state);

  @override
  Object? get lastError => _lastError;

  @override
  String? get lastErrorDescription => _lastErrorDescription;

  @override
  SignalRConnectionInfo get connectionInfo {
    final conn = _connection;
    return SignalRConnectionInfo(
      hubUrl: conn?.baseUrl ?? '',
      state: connectionState,
      connectionId: conn?.connectionId,
      keepAliveInterval: Duration(
        milliseconds: conn?.keepAliveIntervalInMilliseconds ?? 5000,
      ),
      serverTimeout: Duration(
        milliseconds: conn?.serverTimeoutInMilliseconds ?? 15000,
      ),
      lastReceivedAt: _lastReceivedAt,
      lastError: _lastError,
      lastErrorDescription: _lastErrorDescription,
    );
  }

  @override
  Stream<SignalRAppEvent> get events => _events.stream;

  @override
  Future<void> connect() => _connectInternal();

  Future<void> _connectInternal({bool isRetryAfter401 = false}) async {
    final conn = _connection;
    if (conn == null) return;
    if (connectionState == SignalRConnectionState.connected ||
        connectionState == SignalRConnectionState.connecting ||
        connectionState == SignalRConnectionState.reconnecting) {
      return;
    }
    _emitConnection(SignalRConnectionState.connecting);
    AppLogger.instance.info(
      'SignalR connecting (retryAfter401: $isRetryAfter401)',
      category: 'signalr',
      event: 'connecting',
    );
    try {
      await conn.start();
      _lastError = null;
      _lastErrorDescription = null;
      _emitConnection(SignalRConnectionState.connected);
      AppLogger.instance.info(
        'SignalR connected',
        category: 'signalr',
        event: 'connected',
      );
    } catch (error) {
      AppLogger.instance.error(
        'SignalR connection failed',
        category: 'signalr',
        event: 'connect_failed',
        error: error,
        stackTrace: StackTrace.current,
      );

      final refresh = _refreshToken;
      if (!isRetryAfter401 && _isUnauthorizedError(error) && refresh != null) {
        AppLogger.instance.info(
          'SignalR 401 detected during connect, triggering token refresh...',
          category: 'signalr',
          event: 'refresh_on_401',
        );
        try {
          final currentToken = await _readAccessToken();
          String? newToken = currentToken;
          if (currentToken == null || currentToken.isEmpty || shouldRefreshJwt(currentToken)) {
            newToken = await refresh();
          }
          if (newToken != null && newToken.isNotEmpty) {
            AppLogger.instance.info(
              'SignalR token refreshed, retrying start...',
              category: 'signalr',
              event: 'retry_after_refresh',
            );
            _initConnection();
            return await _connectInternal(isRetryAfter401: true);
          }
        } on TokenRefreshRejectedException catch (rejection) {
          AppLogger.instance.error(
            'SignalR refresh token rejected definitively',
            category: 'signalr',
            event: 'token_refresh_rejected',
            error: rejection,
          );
          _onSessionInvalidated?.call();
        } catch (refreshErr) {
          AppLogger.instance.error(
            'SignalR refresh token attempt failed',
            category: 'signalr',
            event: 'token_refresh_failed',
            error: refreshErr,
          );
        }
      }

      _lastError = error;
      _lastErrorDescription = formatSignalRError(error);
      _emitConnection(SignalRConnectionState.disconnected, error: error);
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    final conn = _connection;
    if (conn != null) {
      await conn.stop();
    }
  }

  @override
  Future<void> restart({bool fast = true}) async {
    if (_isConnectingOrRestarting) return;
    _isConnectingOrRestarting = true;
    AppLogger.instance.info(
      'SignalR restarting (fast: $fast)',
      category: 'signalr',
      event: 'restart',
    );
    try {
      final oldConn = _connection;
      if (oldConn != null) {
        try {
          await oldConn.stop().timeout(
            const Duration(milliseconds: 600),
            onTimeout: () {
              AppLogger.instance.info(
                'SignalR old connection stop timed out, forcing new connection',
                category: 'signalr',
                event: 'stop_timeout',
              );
            },
          );
        } catch (_) {}
      }
      _initConnection();
      await _connectInternal();
    } finally {
      _isConnectingOrRestarting = false;
    }
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _events.close();
  }

  @override
  Future<T?> invoke<T>(String method, {List<Object>? arguments}) async {
    final conn = _connection;
    if (conn == null) {
      throw StateError('SignalR is not connected');
    }
    AppLogger.instance.info('SignalR invoke $method',
        category: 'signalr',
        event: 'invoke',
        context: <String, Object?>{
          'method': method,
          'argumentCount': arguments?.length ?? 0
        });
    return await conn.invoke(method, args: arguments) as T?;
  }

  void _onReceivedMessage(List<Object?>? arguments) {
    final value =
        arguments == null || arguments.isEmpty ? null : arguments.first;
    final envelope = _asMap(value);
    final commandValue = envelope?['command']?.toString();
    final now = DateTime.now();
    _lastReceivedAt = now;
    AppLogger.instance.info('SignalR ReceivedMessage',
        category: 'signalr',
        event: 'received_message',
        context: <String, Object?>{
          'payloadSize': value?.toString().length ?? 0,
          'command': commandValue
        });
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
    AppLogger.instance.info(
      'SignalR ${state.name}',
      category: 'signalr',
      event: 'connection_${state.name}',
      context: <String, Object?>{
        'connectionId': connectionId,
        'error': error?.toString(),
      },
    );
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
    return uri.replace(
      queryParameters: <String, String>{
        ...uri.queryParameters,
        ...deviceContext.signalRQueryParameters,
      },
    ).toString();
  }
}
