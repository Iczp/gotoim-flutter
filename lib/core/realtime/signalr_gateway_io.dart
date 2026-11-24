import 'dart:async';

import 'package:flutter/foundation.dart';
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
    @visibleForTesting
    HubConnection Function(Future<String> Function() accessTokenFactory)?
        hubConnectionFactory,
  }) : _environment = environment,
       _readAccessToken = readAccessToken,
       _deviceContext = deviceContext,
       _refreshToken = refreshToken,
       _onSessionInvalidated = onSessionInvalidated,
       _hubConnectionFactory = hubConnectionFactory {
    _initConnection();
  }

  final AppEnvironment _environment;
  final SignalRAccessTokenReader _readAccessToken;
  final ClientDeviceContext _deviceContext;
  final Future<String?> Function()? _refreshToken;
  final FutureOr<void> Function()? _onSessionInvalidated;
  final HubConnection Function(Future<String> Function() accessTokenFactory)?
      _hubConnectionFactory;

  HubConnection? _connection;
  final StreamController<SignalRAppEvent> _events =
      StreamController<SignalRAppEvent>.broadcast();
  DateTime? _lastReceivedAt;
  Object? _lastError;
  String? _lastErrorDescription;
  bool _isConnectingOrRestarting = false;
  String? _lastAttemptedAccessToken;
  bool _skipNextFactoryProactiveRefresh = false;
  Future<void>? _connectInFlight;

  Future<String> _provideAccessToken() async {
    final skipProactive = _skipNextFactoryProactiveRefresh;
    _skipNextFactoryProactiveRefresh = false;
    var token = await _readAccessToken();
    if (!skipProactive &&
        token != null &&
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
      } on TokenRefreshRejectedException catch (rejection) {
        AppLogger.instance.error(
          'SignalR proactive token refresh rejected definitively',
          category: 'signalr',
          event: 'token_refresh_rejected',
          error: rejection,
        );
        if (rejection.code != 'session_signed_out') {
          await _onSessionInvalidated?.call();
        }
        return '';
      } catch (e) {
        AppLogger.instance.error(
          'SignalR proactive token refresh failed',
          category: 'signalr',
          event: 'proactive_token_refresh_failed',
          error: e,
        );
        if (token != null && isJwtExpired(token)) {
          rethrow;
        }
      }
    }
    if (token != null && token.isNotEmpty) {
      _lastAttemptedAccessToken = token;
    }
    return token ?? '';
  }

  void _initConnection() {
    final conn =
        _hubConnectionFactory != null
            ? _hubConnectionFactory(_provideAccessToken)
            : HubConnectionBuilder()
                .withUrl(
                  _withDeviceQuery(_environment.signalRHubUrl, _deviceContext),
                  options: HttpConnectionOptions(
                    skipNegotiation: _environment.signalRSkipNegotiation,
                    transport: HttpTransportType.WebSockets,
                    accessTokenFactory: _provideAccessToken,
                  ),
                )
                .withAutomaticReconnect(
                  retryDelays: _environment.signalRReconnectDelays,
                )
                .build();

    conn.keepAliveIntervalInMilliseconds = 5000;
    conn.serverTimeoutInMilliseconds = 15000;

    conn.on('ReceivedMessage', _onReceivedMessage);
    for (final cmd in const [
      'created@message',
      'forwarded@message',
      'updated@message',
      'rollbacked@message',
      'deleted@message',
      'cleared@message',
      'changed@session-unit',
      'disposed@session-unit',
      'member-removed@session',
      'member-added@session',
      'member-updated@session',
      'updated@message-badge',
      'updated-badge@message',
      'kicked@connection',
    ]) {
      conn.on(cmd, (args) => _onDirectCommand(cmd, args));
    }
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
    conn.onclose(({error}) async {
      _emitConnection(SignalRConnectionState.disconnected, error: error);
      if (_isUnauthorizedError(error) && _refreshToken != null) {
        AppLogger.instance.info(
          'SignalR onclose error was 401 Unauthorized, refreshing token...',
          category: 'signalr',
          event: 'onclose_401_refresh',
        );
        final newToken = await _refreshTokenAfterUnauthorized(
          failedToken: _lastAttemptedAccessToken,
        );
        if (newToken != null && newToken.isNotEmpty) {
          unawaited(restart(fast: true));
        }
      }
    });

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
  SignalRConnectionState get connectionState => _mapState(_connection?.state);

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
  Future<void> connect() {
    final inFlight = _connectInFlight;
    if (inFlight != null) return inFlight;
    final future = _connectInternal();
    _connectInFlight = future;
    return future.whenComplete(() {
      if (identical(_connectInFlight, future)) {
        _connectInFlight = null;
      }
    });
  }

  Future<String?> _ensureValidTokenBeforeConnect() async {
    var token = await _readAccessToken();
    if (token == null || token.isEmpty) {
      AppLogger.instance.info(
        'SignalR connect check: no access token available',
        category: 'signalr',
        event: 'no_access_token',
      );
      return null;
    }
    if (shouldRefreshJwt(token)) {
      AppLogger.instance.info(
        'SignalR validating token before connect: token expired or expiring soon, refreshing...',
        category: 'signalr',
        event: 'proactive_token_refresh_before_connect',
      );
      final refresh = _refreshToken;
      if (refresh != null) {
        try {
          final refreshed = await refresh();
          if (refreshed != null && refreshed.isNotEmpty) {
            token = refreshed;
          }
        } on TokenRefreshRejectedException catch (rejection) {
          AppLogger.instance.error(
            'SignalR proactive token refresh rejected definitively before connect',
            category: 'signalr',
            event: 'token_refresh_rejected',
            error: rejection,
          );
          if (rejection.code != 'session_signed_out') {
            await _onSessionInvalidated?.call();
          }
          rethrow;
        } catch (e) {
          AppLogger.instance.error(
            'SignalR proactive token refresh failed before connect',
            category: 'signalr',
            event: 'token_refresh_failed',
            error: e,
          );
          if (token != null && isJwtExpired(token)) {
            rethrow;
          }
        }
      }
    }
    return token;
  }

  Future<String?> _refreshTokenAfterUnauthorized({
    required String? failedToken,
  }) async {
    final refresh = _refreshToken;
    if (refresh == null) return null;
    try {
      final currentToken = await _readAccessToken();
      if (currentToken == null || currentToken.isEmpty) {
        return null;
      }
      if (failedToken != null &&
          failedToken.isNotEmpty &&
          currentToken != failedToken &&
          !shouldRefreshJwt(currentToken)) {
        return currentToken;
      }
      return await refresh();
    } on TokenRefreshRejectedException catch (rejection) {
      AppLogger.instance.error(
        'SignalR refresh token rejected definitively',
        category: 'signalr',
        event: 'token_refresh_rejected',
        error: rejection,
      );
      if (rejection.code != 'session_signed_out') {
        await _onSessionInvalidated?.call();
      }
      return null;
    } catch (refreshErr) {
      AppLogger.instance.error(
        'SignalR refresh token attempt failed',
        category: 'signalr',
        event: 'token_refresh_failed',
        error: refreshErr,
      );
      return null;
    }
  }

  Future<void> _connectInternal({bool isRetryAfter401 = false}) async {
    final conn = _connection;
    if (conn == null) return;
    if (connectionState == SignalRConnectionState.connected ||
        connectionState == SignalRConnectionState.connecting ||
        connectionState == SignalRConnectionState.reconnecting) {
      return;
    }

    // 连接前验证 Token：如果已经过期或即将过期（5分钟内），必须先 refreshtoken 再连接
    final String? validToken;
    try {
      validToken = await _ensureValidTokenBeforeConnect();
    } catch (error) {
      _lastError = error;
      _lastErrorDescription = formatSignalRError(error);
      _emitConnection(SignalRConnectionState.disconnected, error: error);
      rethrow;
    }
    if (validToken == null || validToken.isEmpty) {
      _emitConnection(
        SignalRConnectionState.disconnected,
        error: '未获取到有效登录 Token，无法连接实时通道。',
      );
      return;
    }

    _lastAttemptedAccessToken = validToken;
    _emitConnection(SignalRConnectionState.connecting);
    AppLogger.instance.info(
      'SignalR connecting (retryAfter401: $isRetryAfter401)',
      category: 'signalr',
      event: 'connecting',
    );
    try {
      _skipNextFactoryProactiveRefresh = true;
      try {
        await conn.start()?.timeout(const Duration(seconds: 15));
      } finally {
        _skipNextFactoryProactiveRefresh = false;
      }
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

      if (!isRetryAfter401 &&
          _isUnauthorizedError(error) &&
          _refreshToken != null) {
        AppLogger.instance.info(
          'SignalR 401 detected during connect, triggering token refresh...',
          category: 'signalr',
          event: 'refresh_on_401',
        );
        final newToken = await _refreshTokenAfterUnauthorized(
          failedToken: _lastAttemptedAccessToken ?? validToken,
        );
        if (newToken != null && newToken.isNotEmpty) {
          AppLogger.instance.info(
            'SignalR token refreshed, retrying start...',
            category: 'signalr',
            event: 'retry_after_refresh',
          );
          _initConnection();
          return await _connectInternal(isRetryAfter401: true);
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
      try {
        await conn.stop().timeout(
          const Duration(milliseconds: 1500),
          onTimeout: () {
            AppLogger.instance.info(
              'SignalR connection stop timed out during disconnect',
              category: 'signalr',
              event: 'disconnect_timeout',
            );
          },
        );
      } catch (e) {
        AppLogger.instance.error(
          'SignalR disconnect error ignored',
          category: 'signalr',
          error: e,
        );
      }
    }
    _emitConnection(SignalRConnectionState.disconnected);
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
    AppLogger.instance.info(
      'SignalR invoke $method',
      category: 'signalr',
      event: 'invoke',
      context: <String, Object?>{
        'method': method,
        'argumentCount': arguments?.length ?? 0,
      },
    );
    return await conn.invoke(method, args: arguments) as T?;
  }

  void _onReceivedMessage(List<Object?>? arguments) {
    final value =
        arguments == null || arguments.isEmpty ? null : arguments.first;
    final envelope = _asMap(value);
    final commandValue = envelope?['command']?.toString();
    final now = DateTime.now();
    _lastReceivedAt = now;
    debugPrint(
      '[SignalR] ReceivedMessage command=$commandValue args=$arguments',
    );
    AppLogger.instance.info(
      'SignalR ReceivedMessage',
      category: 'signalr',
      event: 'received_message',
      context: <String, Object?>{
        'payloadSize': value?.toString().length ?? 0,
        'command': commandValue,
      },
    );
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
    if (command == SignalRCommand.sessionTyping) {
      final payload = _asMap(envelope['payload']) ?? envelope;
      final sessionId = (payload['sessionId'] ?? '').toString().trim();
      final senderSessionUnitId =
          (payload['senderSessionUnitId'] ?? '').toString().trim();
      final senderName = (payload['senderName'] ?? '').toString().trim();
      final isTyping = payload['isTyping'] == true;
      final action = (payload['action'] ?? 'typing').toString().trim();
      final actionText = payload['actionText']?.toString().trim();

      _events.add(
        SignalRTypingEvent(
          sessionId: sessionId,
          senderSessionUnitId: senderSessionUnitId,
          senderName: senderName.isEmpty ? '对方' : senderName,
          isTyping: isTyping,
          action: action.isEmpty ? 'typing' : action,
          actionText:
              (actionText == null || actionText.isEmpty) ? null : actionText,
          receivedAt: now,
          envelope: envelope,
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

  void _onDirectCommand(String command, List<Object?>? arguments) {
    final value =
        arguments == null || arguments.isEmpty ? null : arguments.first;
    final map = _asMap(value) ?? <String, dynamic>{};
    final now = DateTime.now();
    _lastReceivedAt = now;
    debugPrint(
      '[SignalR] DirectCommand command=$command args=$arguments',
    );
    AppLogger.instance.info(
      'SignalR DirectCommand',
      category: 'signalr',
      event: 'direct_command',
      context: <String, Object?>{
        'payloadSize': value?.toString().length ?? 0,
        'command': command,
      },
    );
    final signalRCmd = SignalRCommand.fromValue(command);
    if (signalRCmd == null) {
      _events.add(
        SignalRUnknownCommandEvent(
          command: command,
          envelope: map,
          receivedAt: now,
        ),
      );
      return;
    }
    final envelope = map.containsKey('payload') || map.containsKey('scopes')
        ? map
        : <String, dynamic>{'command': command, 'payload': map};
    _events.add(
      SignalRCommandEvent(
        command: signalRCmd,
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
