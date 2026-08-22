import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/config/app_environment.dart';

void main() {
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
