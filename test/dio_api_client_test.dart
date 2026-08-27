import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/device/client_device_context.dart';
import 'package:gotoim_flutter/core/network/dio_api_client.dart';
import 'package:gotoim_flutter/core/network/jwt_token_expiry.dart';
import 'package:gotoim_flutter/core/network/token_refresher.dart';
import 'package:gotoim_flutter/core/network/token_storage.dart';

void main() {
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
      throwsA(isA<StateError>()),
    );

    expect(storage.accessToken, isNull);
    expect(storage.refreshToken, isNull);
    expect(invalidations, 1);
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
    throw StateError('No refresh token is available.');
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
