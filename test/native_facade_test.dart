import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/native/native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Native Facade & System Capabilities', () {
    test('Native.system provides initial properties safely', () {
      expect(Native.system.currentBrightness, isNotNull);
      expect(Native.system.currentWindowSize, isNotNull);
      expect(Native.system.onThemeChange, isNotNull);
      expect(Native.system.onResize, isNotNull);
      expect(Native.system.onMemoryWarning, isNotNull);
      expect(Native.system.onUserCaptureScreen, isNotNull);
    });

    test('Native.makePhoneCall returns false for empty phone number', () async {
      final result = await Native.makePhoneCall('');
      expect(result, isFalse);
    });
  });

  group('Native Device Capabilities', () {
    test('Native.getBatteryInfo returns default safe battery info in test environment', () async {
      final info = await Native.getBatteryInfo();
      expect(info.level, isNonNegative);
      expect(info.status, isNotNull);
    });

    test('Native.getScreenBrightness returns valid clamped brightness', () async {
      final brightness = await Native.getScreenBrightness();
      expect(brightness, inInclusiveRange(0.0, 1.0));
    });

    test('Native.vibrate completes without unhandled exception', () async {
      await expectLater(Native.vibrate(HapticFeedbackType.light), completes);
      await expectLater(Native.vibrate(HapticFeedbackType.medium), completes);
      await expectLater(Native.vibrate(HapticFeedbackType.heavy), completes);
      await expectLater(Native.vibrate(HapticFeedbackType.selection), completes);
    });

    test('new device controls safely report unsupported in a test runtime', () async {
      expect(await Native.setFlashlight(true), isFalse);
      expect(await Native.getSystemVolume(), -1);
      expect(await Native.setSystemVolume(0.5), isFalse);
      expect(await Native.setDesktopBadge(7), isFalse);
    });
  });

  group('Native Sensor Lifecycle & Cancellation', () {
    test('Native.sensor manages subscription and cancellation lifecycle safely', () {
      var accCount = 0;
      final accSub = Native.onAccelerometerChange((event) {
        accCount++;
      });
      expect(accSub, isNotNull);
      Native.offAccelerometer();

      var gyroCount = 0;
      final gyroSub = Native.onGyroscopeChange((event) {
        gyroCount++;
      });
      expect(gyroSub, isNotNull);
      Native.offGyroscope();

      var proxCount = 0;
      final proxSub = Native.onProximityChange((event) {
        proxCount++;
      });
      expect(proxSub, isNotNull);
      Native.offProximity();

      expect(accCount, 0);
      expect(gyroCount, 0);
      expect(proxCount, 0);
    });
  });
}
