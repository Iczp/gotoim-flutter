import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/config/app_environment.dart';
import 'package:gotoim_flutter/core/device/client_device_context.dart';
import 'package:gotoim_flutter/core/network/client_credentials_token_storage.dart';
import 'package:gotoim_flutter/core/network/token_storage.dart';
import 'package:gotoim_flutter/features/auth/data/openid_connect_auth_repository.dart';

void main() {
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
