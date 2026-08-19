import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/notifications/local_notification_service_io.dart';
import 'package:gotoim_flutter/core/platform/platform_contract.dart';

void main() {
  test('Windows is exposed as a supported local notification platform', () {
    final service = FlutterLocalNotificationService(
      platformFacade: const _WindowsPlatformFacade(),
    );

    expect(service.support.platform, PlatformKind.windows);
    expect(service.support.isSupported, isTrue);
  });
}

class _WindowsPlatformFacade implements PlatformFacade {
  const _WindowsPlatformFacade();

  @override
  PlatformKind get kind => PlatformKind.windows;

  @override
  bool get isWeb => false;

  @override
  bool get supportsMultipleWindows => true;

  @override
  bool get supportsNativeFilePaths => true;
}
