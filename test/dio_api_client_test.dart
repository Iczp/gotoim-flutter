import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:gotoim_flutter/core/config/app_environment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/device/client_device_context.dart';
import 'package:gotoim_flutter/core/network/dio_api_client.dart';
import 'package:gotoim_flutter/core/network/api_exception.dart';
import 'package:gotoim_flutter/core/network/jwt_token_expiry.dart';
import 'package:gotoim_flutter/core/network/token_refresher.dart';
import 'package:gotoim_flutter/core/network/token_storage.dart';
import 'package:gotoim_flutter/features/session/data/datasources/session_unit_api.dart';

void main() {
  for (final anonymousToken in <String?>[null, '']) {
    test(
      'anonymous 401 does not refresh or invalidate the login page ($anonymousToken)',
      () async {
        final storage = _MemoryTokenStorage(anonymousToken, null);
        final refresher = _FakeRefresher(storage);
        var invalidations = 0;
        final client = DioApiClient(
          dio: _tokenDio([]),
          tokenStorage: storage,
          tokenRefresher: refresher,
          deviceContext: _device,
          onSessionInvalidated: () => invalidations++,
        );
        await expectLater(
          client.get<Map<String, dynamic>>('/public'),
          throwsA(
            isA<ApiException>().having(
              (error) => error.statusCode,
              'statusCode',
              401,
            ),
          ),
        );
        expect(refresher.calls, 0);
        expect(invalidations, 0);
        expect(storage.accessToken, anonymousToken);
      },
    );
  }

  test(
    'a stale refresh from a logged-out session cannot clear a newer login',
    () async {
      final storage = _MemoryTokenStorage('old-token', 'refresh');
      final refresher = _StaleSessionRefresher(storage);
      var invalidated = 0;
      final client = DioApiClient(
        dio: _tokenDio([]),
        tokenStorage: storage,
        tokenRefresher: refresher,
        deviceContext: _device,
        onSessionInvalidated: () => invalidated++,
      );
      final request = client.get<Map<String, dynamic>>('/old-session');
      final rejected = expectLater(
        request,
        throwsA(isA<TokenRefreshRejectedException>()),
      );
      await refresher.started.future;
      await storage.save(
        accessToken: 'new-login-token',
        refreshToken: 'new-login-refresh',
      );
      refresher.complete.complete();
      await rejected;
      expect(storage.accessToken, 'new-login-token');
      expect(invalidated, 0);
    },
  );

  test(
    'online abort accepts the backend 204 response without a JSON map',
    () async {
      final storage = _MemoryTokenStorage('access-token', 'refresh');
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.method, 'POST');
            expect(options.path, '/api/chat/online/abort');
            handler.resolve(
              Response<dynamic>(requestOptions: options, statusCode: 204),
            );
          },
        ),
      );
      final client = DioApiClient(
        dio: dio,
        tokenStorage: storage,
        tokenRefresher: _FakeRefresher(storage),
        deviceContext: _device,
      );
      await SessionUnitApi(client).abortOnlineConnections(
        connectionIds: ['fixture-connection'],
        reason: '验收退出',
      );
    },
  );

  test(
    'device logout addresses an offline device without a connection id',
    () async {
      final storage = _MemoryTokenStorage('access-token', 'refresh');
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.method, 'POST');
            expect(options.path, '${AppEnvironment.defaultEnvironment.appDeviceBaseUrl}/api/app-device/public/device-public/logout');
            expect(options.data['deviceId'], 'offline-device');
            expect(options.data['appId'], 'other-app');
            expect(options.data['allUsers'], false);
            expect(options.data.containsKey('connectionIdList'), false);
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'deviceRecordId': 'record',
                  'revokedSessions': 1,
                  'disconnectRequested': true,
                },
              ),
            );
          },
        ),
      );
      final client = DioApiClient(
        dio: dio,
        tokenStorage: storage,
        tokenRefresher: _FakeRefresher(storage),
        deviceContext: _device,
      );
      await SessionUnitApi(
        client,
      ).logoutDevice(appId: 'other-app', deviceId: 'offline-device');
    },
  );

  test('JWT expiring within five minutes refreshes before HTTP', () async {
    final storage = _MemoryTokenStorage(
      _jwt(DateTime.now().add(const Duration(minutes: 4))),
      'refresh',
    );
    final refresher = _FakeRefresher(storage);
    final tokens = <String?>[];
    final dio = _tokenDio(tokens);
    final client = DioApiClient(
      dio: dio,
      tokenStorage: storage,
      tokenRefresher: refresher,
      deviceContext: _device,
    );

    await client.get<Map<String, dynamic>>('/business');

    expect(refresher.calls, 1);
    expect(tokens, <String>['Bearer fresh-token']);
  });

  test(
    'concurrent requests wait for in-flight pre-refresh and use fresh token without hitting 401',
    () async {
      final storage = _MemoryTokenStorage(
        _jwt(DateTime.now().add(const Duration(minutes: 3))),
        'refresh',
      );
      final refresher = _FakeRefresher(storage);
      final tokens = <String?>[];
      final dio = _tokenDio(tokens);
      final client = DioApiClient(
        dio: dio,
        tokenStorage: storage,
        tokenRefresher: refresher,
        deviceContext: _device,
      );

      final results = await Future.wait(<Future<Map<String, dynamic>>>[
        client.get<Map<String, dynamic>>('/one'),
        client.get<Map<String, dynamic>>('/two'),
        client.get<Map<String, dynamic>>('/three'),
      ]);

      expect(refresher.calls, 1);
      expect(results.length, 3);
      // All requests must send ONLY 'Bearer fresh-token' - no 401 requests sent with old token!
      expect(tokens, <String>[
        'Bearer fresh-token',
        'Bearer fresh-token',
        'Bearer fresh-token',
      ]);
    },
  );

  test('concurrent 401 responses share one refresh and all retry', () async {
    final storage = _MemoryTokenStorage('old-token', 'refresh');
    final refresher = _FakeRefresher(storage);
    final tokens = <String?>[];
    final dio = _tokenDio(tokens);
    final client = DioApiClient(
      dio: dio,
      tokenStorage: storage,
      tokenRefresher: refresher,
      deviceContext: _device,
    );

    final results = await Future.wait(<Future<Map<String, dynamic>>>[
      client.get<Map<String, dynamic>>('/one'),
      client.get<Map<String, dynamic>>('/two'),
      client.get<Map<String, dynamic>>('/three'),
    ]);

    expect(refresher.calls, 1);
    expect(results.length, 3);
    expect(tokens.where((token) => token == 'Bearer fresh-token').length, 3);
  });

  test('JWT expiry parser uses exp without network access', () {
    final expiry = DateTime.utc(2030, 1, 1);
    expect(readJwtExpiry(_jwt(expiry)), expiry);
  });

  test(
    'binary download uses authenticated API client and reports bytes',
    () async {
      final storage = _MemoryTokenStorage('access-token', 'refresh');
      final tokens = <String?>[];
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            tokens.add(options.headers['Authorization']?.toString());
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: <int>[1, 2, 3, 4],
              ),
            );
          },
        ),
      );
      final client = DioApiClient(
        dio: dio,
        tokenStorage: storage,
        tokenRefresher: _FakeRefresher(storage),
        deviceContext: _device,
      );

      final bytes = await client.getBytes('/voice/message.m4a');

      expect(bytes, <int>[1, 2, 3, 4]);
      expect(tokens, <String?>['Bearer access-token']);
    },
  );

  test('missing refresh token clears session and notifies auth once', () async {
    final storage = _MemoryTokenStorage(
      _jwt(DateTime.now().add(const Duration(minutes: 1))),
      null,
    );
    final refresher = _MissingRefreshRefresher(storage);
    var invalidations = 0;
    final client = DioApiClient(
      dio: _tokenDio(<String?>[]),
      tokenStorage: storage,
      tokenRefresher: refresher,
      deviceContext: _device,
      onSessionInvalidated: () => invalidations++,
    );

    await expectLater(
      client.get<Map<String, dynamic>>('/business'),
      throwsA(isA<TokenRefreshRejectedException>()),
    );

    expect(storage.accessToken, isNull);
    expect(storage.refreshToken, isNull);
    expect(invalidations, 1);
  });

  test('temporary refresh failure preserves tokens and login state', () async {
    final access = _jwt(DateTime.now().add(const Duration(minutes: 1)));
    final storage = _MemoryTokenStorage(access, 'refresh');
    var invalidations = 0;
    final client = DioApiClient(
      dio: _tokenDio(<String?>[]),
      tokenStorage: storage,
      tokenRefresher: _TemporaryRefreshFailureRefresher(storage),
      deviceContext: _device,
      onSessionInvalidated: () => invalidations++,
    );

    await expectLater(
      client.get<Map<String, dynamic>>('/business'),
      throwsA(isA<StateError>()),
    );

    expect(storage.accessToken, access);
    expect(storage.refreshToken, 'refresh');
    expect(invalidations, 0);
  });
}

String _jwt(DateTime expiry) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part(<String, Object?>{'alg': 'none'})}.${part(<String, Object?>{'exp': expiry.millisecondsSinceEpoch ~/ 1000})}.';
}

const _device = ClientDeviceContext(
  appId: 'app',
  appName: 'app',
  appVersion: '1',
  deviceId: 'device',
  deviceType: 'test',
  platform: 'test',
  brand: '',
  model: '',
  browser: '',
  pushClientId: '',
);

class _MemoryTokenStorage implements TokenStorage {
  _MemoryTokenStorage(this.accessToken, this.refreshToken);
  String? accessToken;
  String? refreshToken;
  @override
  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
  }

  @override
  Future<String?> readAccessToken() async => accessToken;
  @override
  Future<String?> readRefreshToken() async => refreshToken;
  @override
  Future<bool> hasToken() async => accessToken?.isNotEmpty == true;
  @override
  Future<void> save({
    required String accessToken,
    required String refreshToken,
  }) async {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
  }
}

class _FakeRefresher implements TokenRefresher {
  _FakeRefresher(this.storage);
  final _MemoryTokenStorage storage;
  int calls = 0;
  @override
  Future<void> clearSession() => storage.clear();
  @override
  Future<void> refreshAccessToken() async {
    calls++;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await storage.save(accessToken: 'fresh-token', refreshToken: 'refresh');
  }
}

class _MissingRefreshRefresher implements TokenRefresher {
  _MissingRefreshRefresher(this.storage);
  final _MemoryTokenStorage storage;

  @override
  Future<void> clearSession() => storage.clear();

  @override
  Future<void> refreshAccessToken() async {
    throw const TokenRefreshRejectedException(
      'No refresh token is available.',
      code: 'missing_refresh_token',
    );
  }
}

class _TemporaryRefreshFailureRefresher implements TokenRefresher {
  _TemporaryRefreshFailureRefresher(this.storage);
  final _MemoryTokenStorage storage;

  @override
  Future<void> clearSession() => storage.clear();

  @override
  Future<void> refreshAccessToken() async {
    throw StateError('Network is temporarily unavailable');
  }
}

Dio _tokenDio(List<String?> tokens) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = options.headers['Authorization']?.toString();
        tokens.add(token);
        if (token == 'Bearer fresh-token') {
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: <String, dynamic>{'ok': true},
            ),
          );
        } else {
          handler.reject(
            DioException(
              requestOptions: options,
              response: Response<dynamic>(
                requestOptions: options,
                statusCode: 401,
              ),
            ),
          );
        }
      },
    ),
  );
  return dio;
}

class _StaleSessionRefresher implements TokenRefresher {
  _StaleSessionRefresher(this.storage);
  final _MemoryTokenStorage storage;
  final started = Completer<void>();
  final complete = Completer<void>();
  @override
  Future<void> clearSession() => storage.clear();
  @override
  Future<void> refreshAccessToken() async {
    started.complete();
    await complete.future;
    throw const TokenRefreshRejectedException(
      'Session changed.',
      code: 'session_signed_out',
    );
  }
}
