import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/config/app_environment.dart';
import 'package:gotoim_flutter/core/device/client_device_context.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';
import 'package:gotoim_flutter/features/app_update/application/app_update_service.dart';
import 'package:gotoim_flutter/features/app_update/data/datasources/app_update_api.dart';
import 'package:package_info_plus/package_info_plus.dart';

class RecordingClient implements ApiClient {
  Map<String, Object?>? query;
  @override
  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    bool retryOnUnauthorized = true,
  }) async {
    this.query = query;
    return null as T;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('checks using the installed application build number', () async {
    PackageInfo.setMockInitialValues(
      appName: 'app',
      packageName: 'app.test',
      version: '1.2.3',
      buildNumber: '42',
      buildSignature: '',
    );
    final client = RecordingClient();
    final environment = AppEnvironment.defaultEnvironment;
    final service = AppUpdateService(
      api: AppUpdateApi(client, environment: environment),
      environment: environment,
      deviceContext: const ClientDeviceContext(
        appId: 'app',
        appName: 'app',
        appVersion: '1',
        deviceId: 'device',
        deviceType: 'phone',
        platform: 'android',
        brand: '',
        model: '',
        browser: '',
        pushClientId: '',
      ),
    );
    await service.checkUpdate();
    expect(service.currentVersionCode, 42);
    expect(client.query?['versionCode'], 42);
    service.dispose();
  });
}
