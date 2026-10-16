import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/config/app_environment.dart';
import 'package:gotoim_flutter/core/device/client_device_context.dart';
import 'package:gotoim_flutter/core/network/client_credentials_token_storage.dart';
import 'package:gotoim_flutter/core/network/token_storage.dart';
import 'package:gotoim_flutter/core/network/token_refresher.dart';
import 'package:gotoim_flutter/features/auth/data/openid_connect_auth_repository.dart';

void main() {
  test(
    'a refresh completing after device logout cannot restore credentials',
    () async {
      dotenv.loadFromString(envString: 'AUTH_BASE_URL=https://example.test');
      final storage = _MemoryTokenStorage(
        accessToken: 'old',
        refreshToken: 'refresh',
      );
      final dio = Dio();
      final received = Completer<(RequestOptions, RequestInterceptorHandler)>();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            received.complete((options, handler));
          },
        ),
      );
      final repository = OpenIdConnectAuthRepository(
        dio: dio,
        environment: AppEnvironment.fromDotEnv(AppFlavor.development),
        tokenStorage: storage,
        clientCredentialsTokenStorage: ClientCredentialsTokenStorage(),
        deviceContext: _deviceContext,
      );
      final refresh = repository.refreshSession();
      final rejected = expectLater(
        refresh,
        throwsA(isA<TokenRefreshRejectedException>()),
      );
      final (request, handler) = await received.future;
      await repository.clearSession();
      handler.resolve(
        Response<dynamic>(
          requestOptions: request,
          statusCode: 200,
          data: {
            'access_token': 'late-token',
            'refresh_token': 'late-refresh',
            'expires_in': 3600,
            'token_type': 'Bearer',
          },
        ),
      );
      await rejected;
      expect(storage.accessToken, isNull);
      expect(storage.refreshToken, isNull);
    },
  );

  test(
    'logout uses device identity and always removes local tokens after a network failure',
    () async {
      dotenv.loadFromString(envString: 'AUTH_BASE_URL=https://example.test');
      final storage = _MemoryTokenStorage(
        accessToken: 'old',
        refreshToken: 'refresh',
      );
      final dio = Dio();
      var called = false;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.endsWith('/api/chat/device/logout')) {
              called = true;
              expect(options.data['deviceId'], _deviceContext.deviceId);
              expect(options.data['appId'], _deviceContext.appId);
              expect(options.data['allUsers'], false);
            }
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
              ),
            );
          },
        ),
      );
      final repository = OpenIdConnectAuthRepository(
        dio: dio,
        environment: AppEnvironment.fromDotEnv(AppFlavor.development),
        tokenStorage: storage,
        clientCredentialsTokenStorage: ClientCredentialsTokenStorage(),
        deviceContext: _deviceContext,
      );
      await repository.logout();
      expect(called, true);
      expect(storage.accessToken, isNull);
      expect(storage.refreshToken, isNull);
    },
  );

  test('restores a stored session without a network refresh', () async {
    dotenv.loadFromString(envString: 'AUTH_BASE_URL=https://example.test');
    final storage = _MemoryTokenStorage(
      accessToken: 'expired-token',
      refreshToken: 'refresh-token',
    );
    final repository = OpenIdConnectAuthRepository(
      dio: Dio(),
      environment: AppEnvironment.fromDotEnv(AppFlavor.development),
      tokenStorage: storage,
      clientCredentialsTokenStorage: ClientCredentialsTokenStorage(),
      deviceContext: _deviceContext,
    );

    expect(await repository.restoreSession(), isTrue);
    expect(storage.accessToken, 'expired-token');
    expect(storage.refreshToken, 'refresh-token');
  });
}

const _deviceContext = ClientDeviceContext(
  appId: 'test-app',
  appName: 'Test App',
  appVersion: '1.0.0',
  deviceId: 'test-device',
  deviceType: 'test',
  platform: 'test',
  brand: '',
  model: '',
  browser: '',
  pushClientId: '',
);

class _MemoryTokenStorage implements TokenStorage {
  _MemoryTokenStorage({this.accessToken, this.refreshToken});

  String? accessToken;
  String? refreshToken;

  @override
  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
  }

  @override
  Future<bool> hasToken() async => accessToken?.isNotEmpty == true;

  @override
  Future<String?> readAccessToken() async => accessToken;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> save({
    required String accessToken,
    required String refreshToken,
  }) async {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
  }
}
