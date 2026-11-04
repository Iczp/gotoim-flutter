import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/config/app_environment.dart';

void main() {
  test('AppDevice uses its configured service address and falls back to the API gateway', () {
    dotenv.loadFromString(envString: 'API_BASE_URL=http://gateway\nAPP_DEVICE_BASE_URL=http://device:51631/');
    var environment = AppEnvironment.fromDotEnv(AppFlavor.development);
    expect(environment.appDeviceUrl('/api/app-device/public/app-version/latest'),
        'http://device:51631/api/app-device/public/app-version/latest');

    dotenv.loadFromString(envString: 'API_BASE_URL=http://gateway\nAPP_DEVICE_BASE_URL=');
    environment = AppEnvironment.fromDotEnv(AppFlavor.development);
    expect(environment.appDeviceUrl('/api/app-device/public/app-version/latest'),
        'http://gateway/api/app-device/public/app-version/latest');
  });

  for (final file in [
    '.env.development',
    '.env.staging',
    '.env.production',
    '.env.example',
  ]) {
    test('$file requests every deployed service audience', () {
      dotenv.loadFromString(envString: File(file).readAsStringSync());
      final environment = AppEnvironment.fromDotEnv(AppFlavor.development);
      expect(
        environment.authScope.split(' '),
        containsAll([
          'IM',
          'Chat',
          'Cms',
          'Social',
          'AppStatistic',
          'AppDevice',
        ]),
      );
      // Anonymous scan-login uses the IM-hosted hub, not a user session.
      expect(environment.scanLoginAuthScope, 'IM');
      expect(environment.standaloneToolWindows, isFalse);
      expect(environment.standaloneSettingsWindow, isFalse);
      expect(environment.standaloneFileServerWindow, isFalse);
    });
  }

  test('reads the JS Bridge harness URL from the active environment', () {
    dotenv.loadFromString(
      envString:
          'JS_BRIDGE_HARNESS_URL=http://10.0.5.20:4173\n'
          'JS_BRIDGE_UPLOAD_URL=http://10.0.5.20:4173/upload',
    );
    final environment = AppEnvironment.fromDotEnv(AppFlavor.development);

    expect(environment.jsBridgeHarnessUrl, 'http://10.0.5.20:4173');
    expect(environment.jsBridgeUploadUrl, 'http://10.0.5.20:4173/upload');
    expect(environment.deepLinkCustomSchemes, ['gotoim-dev', 'gotoim']);
    expect(environment.deepLinkAllowedHosts, ['gotoim.com']);
  });

  test('standalone tool windows default to false and respect environment overrides', () {
    dotenv.loadFromString(envString: 'APP_NAME=GotoIM');
    var environment = AppEnvironment.fromDotEnv(AppFlavor.development);
    expect(environment.standaloneToolWindows, isFalse);
    expect(environment.standaloneSettingsWindow, isFalse);
    expect(environment.standaloneFileServerWindow, isFalse);

    // Global switch enables both by default
    dotenv.loadFromString(envString: 'STANDALONE_TOOL_WINDOWS=true');
    environment = AppEnvironment.fromDotEnv(AppFlavor.development);
    expect(environment.standaloneToolWindows, isTrue);
    expect(environment.standaloneSettingsWindow, isTrue);
    expect(environment.standaloneFileServerWindow, isTrue);

    // Specific switches override global switch
    dotenv.loadFromString(
      envString:
          'STANDALONE_TOOL_WINDOWS=true\n'
          'STANDALONE_SETTINGS_WINDOW=false\n'
          'STANDALONE_FILE_SERVER_WINDOW=true',
    );
    environment = AppEnvironment.fromDotEnv(AppFlavor.development);
    expect(environment.standaloneToolWindows, isTrue);
    expect(environment.standaloneSettingsWindow, isFalse);
    expect(environment.standaloneFileServerWindow, isTrue);
  });
}
