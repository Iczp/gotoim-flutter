import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/capabilities/client_capability_models.dart';
import 'package:gotoim_flutter/core/capabilities/client_capability_service.dart';
import 'package:gotoim_flutter/core/config/app_environment.dart';
import 'package:gotoim_flutter/core/device/client_device_context.dart';
import 'package:gotoim_flutter/core/device/device_registration_api.dart';
import 'package:gotoim_flutter/core/logging/log_sanitizer.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';
import 'package:gotoim_flutter/core/network/client_credentials_token_storage.dart';
import 'package:gotoim_flutter/core/network/secure_token_storage.dart';
import 'package:gotoim_flutter/core/platform/platform_contract.dart';
import 'package:gotoim_flutter/features/auth/data/openid_connect_auth_repository.dart';

const device = ClientDeviceContext(
  appId: 'app',
  appName: 'App',
  appVersion: '1.0',
  deviceId: 'client-fingerprint',
  deviceType: 'phone',
  platform: 'android',
  brand: 'brand',
  model: 'model',
  browser: '',
  pushClientId: '',
);

AppEnvironment environment({bool independent = false}) {
  dotenv.loadFromString(
    envString:
        'APP_ID=app\nAPI_BASE_URL=https://api.example.test\nAUTH_BASE_URL=https://auth.example.test\nAUTH_CLIENT_ID=mobile\n'
        '${independent ? 'DEVICE_REGISTRATION_API_PATH=/api/app-device/public/device-public/register' : ''}',
  );
  return AppEnvironment.fromDotEnv(AppFlavor.development);
}

class FakeCapabilities implements ClientCapabilityService {
  @override
  Future<ClientSystemInfo> getSystemInfo() async => const ClientSystemInfo(
    platform: PlatformKind.android,
    isWeb: false,
    locale: 'zh',
    brightness: 'light',
    devicePixelRatio: 2.5,
    windowWidth: 400,
    windowHeight: 800,
    screenWidth: 1080,
    screenHeight: 2400,
    safeAreaTop: 20,
    safeAreaRight: 0,
    safeAreaBottom: 0,
    safeAreaLeft: 0,
    appId: 'app',
    appName: 'App',
    appVersion: '1.0',
  );
  @override
  Future<ClientDeviceInfo> getDeviceInfo() async => const ClientDeviceInfo(
    platform: PlatformKind.android,
    appScopedDeviceId: 'client-fingerprint',
    deviceType: 'phone',
    brand: 'brand',
    model: 'model',
    systemName: 'android',
    systemVersion: '15',
    isPhysicalDevice: true,
    browser: 'browser',
    source: 'fixture',
  );
  @override
  Future<ClientNetworkStatus> getNetworkType() async => ClientNetworkStatus(
    types: const [ClientNetworkType.wifi],
    observedAt: DateTime.now(),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeApi implements ApiClient {
  final requests = <Map<String, Object?>>[];
  final paths = <String>[];
  final replies = <Object?>[];
  Completer<Object?>? pending;
  @override
  Future<T> post<T>(
    String path, {
    Map<String, Object?>? query,
    Object? data,
    Map<String, String>? headers,
    bool retryOnUnauthorized = true,
  }) async {
    paths.add(path);
    requests.add(Map<String, Object?>.from(data as Map));
    if (pending != null) return await pending!.future as T;
    return replies.removeAt(0) as T;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DeviceRegistrationApi registration(FakeApi api, {bool independent = false}) =>
    DeviceRegistrationApi(
      apiClient: api,
      capabilities: FakeCapabilities(),
      deviceContext: device,
      environment: environment(independent: independent),
      readClientCredentialsToken: () async => 'fixture-token',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'AppDevice registrations retain client identity and never send a credential',
    () async {
      final api =
          FakeApi()
            ..replies.addAll([
              {'id': 'record'},
              {'id': 'record'},
            ]);
      final client = registration(api);
      await client.register();
      await client.register();
      expect(api.paths, [
        'https://api.example.test/api/app-device/public/device-public/register',
        'https://api.example.test/api/app-device/public/device-public/register',
      ]);
      for (final body in api.requests) {
        expect(body['deviceId'], device.deviceId);
        final profile = body['profile'] as Map;
        expect(profile['screenWidth'], 1080);
        expect(profile['pixelRatio'], 2.5);
        expect(body.containsKey('registrationProof'), isFalse);
      }
    },
  );
  test(
    'independent API nests all 61 metadata fields and excludes managed state',
    () async {
      final api =
          FakeApi()
            ..replies.add({
              'device': {'deviceId': device.deviceId},
            });
      await registration(api, independent: true).register();
      final body = api.requests.single;
      final profile = body['profile'] as Map;
      expect(api.paths.single, 'https://api.example.test/api/app-device/public/device-public/register');
      expect(body['deviceId'], device.deviceId);
      expect(profile.length, 61);
      expect(profile['browserName'], 'browser');
      expect(profile['screenHeight'], 2400);
      expect(profile['wifiEnabled'], true);
      expect(profile.containsKey('isEnabled'), isFalse);
      expect(body.containsKey('isEnabled'), isFalse);
    },
  );
  test(
    'registration coalesces while authenticated login proceeds independently',
    () async {
      final api = FakeApi()..pending = Completer<Object?>();
      final client = registration(api);
      final requests = <RequestOptions>[];
      final dio =
          Dio()
            ..interceptors.add(
              InterceptorsWrapper(
                onRequest: (request, handler) {
                  requests.add(request);
                  handler.resolve(
                    Response(
                      requestOptions: request,
                      data: {
                        'access_token': 'access',
                        'refresh_token': 'refresh',
                        'expires_in': 3600,
                      },
                    ),
                  );
                },
              ),
            );
      final auth = OpenIdConnectAuthRepository(
        dio: dio,
        environment: environment(),
        tokenStorage: SecureTokenStorage(),
        clientCredentialsTokenStorage: ClientCredentialsTokenStorage(),
        deviceContext: device,
      );
      final first = client.register();
      final second = client.register();
      await auth
          .login(username: 'user', password: 'fixture-password')
          .timeout(const Duration(seconds: 2));
      expect(requests.length, 1);
      expect(api.requests.length, 1);
      expect(
        requests.single.headers.containsKey('AppDevice-Registration-Proof'),
        isFalse,
      );
      api.pending!.complete({'id': 'record'});
      await Future.wait([first, second]);
      await auth.getDeviceRegistrationAccessToken().timeout(
        const Duration(seconds: 2),
      );
      expect(requests.last.data['scope'], 'Chat');
      expect(
        requests.last.headers.containsKey('AppDevice-Registration-Proof'),
        isFalse,
      );
    },
  );
  test('legacy sensitive fields remain redacted from diagnostics', () {
    expect(
      LogSanitizer.sanitize({
        'registrationProof': 'secret',
        'AppDevice-Registration-Proof': 'secret',
      }),
      {'registrationProof': '***', 'AppDevice-Registration-Proof': '***'},
    );
  });
}
