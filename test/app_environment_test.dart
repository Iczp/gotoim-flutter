import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/config/app_environment.dart';

void main() {
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
}
