import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/config/app_environment.dart';
import 'package:gotoim_flutter/core/device/client_device_context.dart';
import 'package:gotoim_flutter/core/network/token_refresher.dart';
import 'package:gotoim_flutter/core/realtime/signalr_gateway.dart';
import 'package:gotoim_flutter/core/realtime/signalr_gateway_io.dart';
import 'package:signalr_netcore/signalr_client.dart';

void main() {
  test(
    'expired JWT with transient refresh failure aborts before start without duplicate refresh or session invalidation',
    () async {
      final storedToken = _jwt(DateTime.now().subtract(const Duration(minutes: 2)));
      var refreshCalls = 0;
      var invalidations = 0;
      var startCalls = 0;

      final gateway = SignalRNetcoreGateway(
        environment: AppEnvironment.defaultEnvironment,
        readAccessToken: () async => storedToken,
        deviceContext: _deviceContext,
        refreshToken: () async {
          refreshCalls++;
          throw StateError('Temporary network timeout');
        },
        onSessionInvalidated: () => invalidations++,
        hubConnectionFactory: (accessTokenFactory) => _FakeHubConnection(
          onStart: () async {
            startCalls++;
            await accessTokenFactory();
          },
        ),
      );
      addTearDown(gateway.dispose);

      await expectLater(gateway.connect(), throwsA(isA<StateError>()));
      expect(refreshCalls, 1);
      expect(startCalls, 0);
      expect(invalidations, 0);
      expect(gateway.connectionState, SignalRConnectionState.disconnected);
    },
  );

  test(
    'near-expiry JWT with transient refresh failure connects once without duplicate refresh in accessTokenFactory',
    () async {
      final nearExpiryToken = _jwt(DateTime.now().add(const Duration(minutes: 3)));
      var refreshCalls = 0;
      var invalidations = 0;
      final tokensUsed = <String>[];

      final gateway = SignalRNetcoreGateway(
        environment: AppEnvironment.defaultEnvironment,
        readAccessToken: () async => nearExpiryToken,
        deviceContext: _deviceContext,
        refreshToken: () async {
          refreshCalls++;
          throw StateError('Temporary network timeout');
        },
        onSessionInvalidated: () => invalidations++,
        hubConnectionFactory: (accessTokenFactory) => _FakeHubConnection(
          onStart: () async {
            tokensUsed.add(await accessTokenFactory());
          },
        ),
      );
      addTearDown(gateway.dispose);

      await gateway.connect();
      expect(refreshCalls, 1);
      expect(tokensUsed, <String>[nearExpiryToken]);
      expect(invalidations, 0);
      expect(gateway.connectionState, SignalRConnectionState.connected);
    },
  );

  test(
    'definitive refresh rejection invalidates session once while session_signed_out does not',
    () async {
      final expiredToken = _jwt(DateTime.now().subtract(const Duration(minutes: 1)));
      var invalidations = 0;
      var rejectionCode = 'invalid_grant';

      final gateway = SignalRNetcoreGateway(
        environment: AppEnvironment.defaultEnvironment,
        readAccessToken: () async => expiredToken,
        deviceContext: _deviceContext,
        refreshToken: () async {
          throw TokenRefreshRejectedException('Rejected', code: rejectionCode);
        },
        onSessionInvalidated: () => invalidations++,
        hubConnectionFactory: (_) => _FakeHubConnection(onStart: () async {}),
      );
      addTearDown(gateway.dispose);

      await expectLater(
        gateway.connect(),
        throwsA(isA<TokenRefreshRejectedException>()),
      );
      expect(invalidations, 1);

      rejectionCode = 'session_signed_out';
      await expectLater(
        gateway.connect(),
        throwsA(isA<TokenRefreshRejectedException>()),
      );
      expect(invalidations, 1);
    },
  );

  test(
    '401 during connect forces refresh even when JWT is not locally expired and retries once',
    () async {
      var storedToken = _jwt(DateTime.now().add(const Duration(hours: 1)));
      final freshToken = _jwt(DateTime.now().add(const Duration(hours: 2)));
      var refreshCalls = 0;
      var invalidations = 0;
      final attemptedTokens = <String>[];

      final gateway = SignalRNetcoreGateway(
        environment: AppEnvironment.defaultEnvironment,
        readAccessToken: () async => storedToken,
        deviceContext: _deviceContext,
        refreshToken: () async {
          refreshCalls++;
          storedToken = freshToken;
          return storedToken;
        },
        onSessionInvalidated: () => invalidations++,
        hubConnectionFactory: (accessTokenFactory) => _FakeHubConnection(
          onStart: () async {
            final token = await accessTokenFactory();
            attemptedTokens.add(token);
            if (token != freshToken) {
              throw Exception('HttpError: Status code 401 Unauthorized');
            }
          },
        ),
      );
      addTearDown(gateway.dispose);

      await gateway.connect();
      expect(refreshCalls, 1);
      expect(attemptedTokens.length, 2);
      expect(attemptedTokens.last, freshToken);
      expect(invalidations, 0);
      expect(gateway.connectionState, SignalRConnectionState.connected);
    },
  );

  test(
    '401 during connect reuses token already refreshed by another request without extra refresh',
    () async {
      final firstToken = _jwt(DateTime.now().add(const Duration(hours: 1)));
      final externallyRefreshedToken =
          _jwt(DateTime.now().add(const Duration(hours: 2)));
      var storedToken = firstToken;
      var refreshCalls = 0;
      var startAttempts = 0;

      final gateway = SignalRNetcoreGateway(
        environment: AppEnvironment.defaultEnvironment,
        readAccessToken: () async => storedToken,
        deviceContext: _deviceContext,
        refreshToken: () async {
          refreshCalls++;
          return storedToken;
        },
        hubConnectionFactory: (accessTokenFactory) => _FakeHubConnection(
          onStart: () async {
            startAttempts++;
            final token = await accessTokenFactory();
            if (startAttempts == 1) {
              // Simulate DioApiClient completing a refresh while SignalR start was in-flight.
              storedToken = externallyRefreshedToken;
              throw Exception('Status code: 401');
            }
            expect(token, externallyRefreshedToken);
          },
        ),
      );
      addTearDown(gateway.dispose);

      await gateway.connect();
      expect(refreshCalls, 0);
      expect(startAttempts, 2);
      expect(gateway.connectionState, SignalRConnectionState.connected);
    },
  );

  test(
    'onclose 401 forces refresh on non-expired JWT and invalidates session on definitive rejection',
    () async {
      var storedToken = _jwt(DateTime.now().add(const Duration(hours: 1)));
      final freshToken = _jwt(DateTime.now().add(const Duration(hours: 2)));
      var refreshCalls = 0;
      var invalidations = 0;
      var rejectNextRefresh = false;
      _FakeHubConnection? activeConnection;

      final gateway = SignalRNetcoreGateway(
        environment: AppEnvironment.defaultEnvironment,
        readAccessToken: () async => storedToken,
        deviceContext: _deviceContext,
        refreshToken: () async {
          refreshCalls++;
          if (rejectNextRefresh) {
            throw const TokenRefreshRejectedException(
              'The token has been revoked or is no longer valid. Sign in again.',
              code: 'invalid_grant',
            );
          }
          storedToken = freshToken;
          return storedToken;
        },
        onSessionInvalidated: () => invalidations++,
        hubConnectionFactory: (accessTokenFactory) {
          return activeConnection = _FakeHubConnection(
            onStart: () async {
              await accessTokenFactory();
            },
          );
        },
      );
      addTearDown(gateway.dispose);

      await gateway.connect();
      expect(gateway.connectionState, SignalRConnectionState.connected);

      activeConnection!.triggerClose(Exception('401 Unauthorized'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(refreshCalls, 1);
      expect(invalidations, 0);
      expect(gateway.connectionState, SignalRConnectionState.connected);

      rejectNextRefresh = true;
      activeConnection!.triggerClose(Exception('401 Unauthorized'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(refreshCalls, 2);
      expect(invalidations, 1);
    },
  );

  test(
    '401 during connect with transient refresh failure preserves session',
    () async {
      final validJwt = _jwt(DateTime.now().add(const Duration(hours: 1)));
      var refreshCalls = 0;
      var invalidations = 0;

      final gateway = SignalRNetcoreGateway(
        environment: AppEnvironment.defaultEnvironment,
        readAccessToken: () async => validJwt,
        deviceContext: _deviceContext,
        refreshToken: () async {
          refreshCalls++;
          throw StateError('Network unreachable');
        },
        onSessionInvalidated: () => invalidations++,
        hubConnectionFactory: (accessTokenFactory) => _FakeHubConnection(
          onStart: () async {
            await accessTokenFactory();
            throw Exception('401 Unauthorized');
          },
        ),
      );
      addTearDown(gateway.dispose);

      await expectLater(gateway.connect(), throwsA(isA<Exception>()));
      expect(refreshCalls, 1);
      expect(invalidations, 0);
    },
  );
}

class _FakeHubConnection extends Fake implements HubConnection {
  _FakeHubConnection({required this.onStart});

  final Future<void> Function() onStart;
  final List<ClosedCallback> _closedCallbacks = <ClosedCallback>[];
  HubConnectionState _state = HubConnectionState.Disconnected;

  @override
  int keepAliveIntervalInMilliseconds = 5000;

  @override
  int serverTimeoutInMilliseconds = 15000;

  @override
  HubConnectionState? get state => _state;

  @override
  String? get baseUrl => 'http://example.test/signalr-hubs/chat';

  @override
  String? get connectionId => 'fake-conn';

  @override
  void on(String methodName, MethodInvocationFunc newMethod) {}

  @override
  void onreconnecting(ReconnectingCallback callback) {}

  @override
  void onreconnected(ReconnectedCallback callback) {}

  @override
  void onclose(ClosedCallback callback) {
    _closedCallbacks.add(callback);
  }

  @override
  Future<void>? start() async {
    _state = HubConnectionState.Connecting;
    try {
      await onStart();
      _state = HubConnectionState.Connected;
    } catch (e) {
      _state = HubConnectionState.Disconnected;
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    _state = HubConnectionState.Disconnected;
  }

  void triggerClose(Exception error) {
    _state = HubConnectionState.Disconnected;
    for (final cb in List<ClosedCallback>.from(_closedCallbacks)) {
      cb(error: error);
    }
  }
}

String _jwt(DateTime expiry) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part(<String, Object?>{'alg': 'none'})}.${part(<String, Object?>{'exp': expiry.toUtc().millisecondsSinceEpoch ~/ 1000})}.';
}

const _deviceContext = ClientDeviceContext(
  appId: 'app',
  appName: 'app',
  appVersion: '1.0.0',
  deviceId: 'device',
  deviceType: 'test',
  platform: 'test',
  brand: '',
  model: '',
  browser: '',
  pushClientId: '',
);
