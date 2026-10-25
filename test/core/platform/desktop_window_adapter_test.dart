import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/platform/desktop_window_adapter.dart';
import 'package:gotoim_flutter/core/platform/desktop_window_capabilities.dart';

void main() {
  group('DesktopWindowCapabilities', () {
    test('Windows capability matrix is complete and verified', () {
      final caps = DesktopWindowCapabilities.windows();
      expect(caps.platformName, 'Windows');
      expect(caps.supportsMultipleWindows, isTrue);
      expect(caps.supportsWindowDocking, isTrue);
      expect(caps.supportsNativeProfileFlyout, isTrue);
      expect(caps.supportsNativeFirstFrameAck, isTrue);
      expect(caps.supportsNativeScreenCapture, isTrue);
      expect(caps.supportsBuiltinAnnotation, isTrue);
      expect(caps.supportsAlwaysOnTop, isTrue);
      expect(caps.supportsVideoPlayback, isTrue);
      expect(caps.supportsCustomTitleBar, isTrue);
      expect(caps.supportsTray, isTrue);
      expect(caps.statusReasons.containsKey('supportsWindowDocking'), isTrue);
    });

    test('macOS exposes controls but gates incomplete native protocols', () {
      final caps = DesktopWindowCapabilities.macos();
      expect(caps.supportsMultipleWindows, isTrue);
      expect(caps.supportsAlwaysOnTop, isTrue);
      expect(caps.supportsCustomTitleBar, isTrue);
      expect(caps.supportsWindowDocking, isFalse);
      expect(caps.supportsNativeProfileFlyout, isFalse);
      expect(caps.supportsNativeFirstFrameAck, isFalse);
      expect(caps.supportsNativeScreenCapture, isFalse);
      expect(caps.supportsBuiltinAnnotation, isFalse);
      expect(
        caps.statusReasons['supportsNativeFirstFrameAck'],
        contains('Flutter'),
      );
    });

    test('Linux does not mistake main-view first-frame for per-engine ack', () {
      final caps = DesktopWindowCapabilities.linux();
      expect(caps.supportsMultipleWindows, isTrue);
      expect(caps.supportsWindowDocking, isFalse);
      expect(caps.supportsVideoPlayback, isFalse);
      expect(caps.supportsNativeFirstFrameAck, isFalse);
      expect(caps.supportsBuiltinAnnotation, isFalse);
      expect(caps.supportsNativeScreenCapture, isFalse);
    });

    test('Fallback capability matrix reports everything unsupported', () {
      final caps = DesktopWindowCapabilities.fallback('Android');
      expect(caps.platformName, 'Android');
      expect(caps.supportsMultipleWindows, isFalse);
      expect(caps.supportsWindowDocking, isFalse);
      expect(caps.supportsVideoPlayback, isFalse);
    });
  });

  group('DesktopWindowAdapter resolution', () {
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      DesktopWindowAdapter.setAdapterForTesting(null);
    });

    test('Resolves Windows adapter on Windows target platform', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(DesktopWindowAdapter.isWindows, isTrue);
      expect(
        DesktopWindowAdapter.current,
        isA<WindowsDesktopWindowPlatformAdapter>(),
      );
      expect(DesktopWindowAdapter.capabilities.supportsWindowDocking, isTrue);
    });

    test(
      'Resolves macOS adapter on macOS target platform with native capabilities',
      () {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        expect(DesktopWindowAdapter.isMacOS, isTrue);
        expect(
          DesktopWindowAdapter.current,
          isA<MacosDesktopWindowPlatformAdapter>(),
        );
        expect(
          DesktopWindowAdapter.capabilities.supportsWindowDocking,
          isFalse,
        );
        expect(
          DesktopWindowAdapter.capabilities.supportsNativeProfileFlyout,
          isFalse,
        );
      },
    );

    test(
      'Resolves Linux adapter on Linux target platform without silent fake-success',
      () {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        expect(DesktopWindowAdapter.isLinux, isTrue);
        expect(
          DesktopWindowAdapter.current,
          isA<LinuxDesktopWindowPlatformAdapter>(),
        );
        expect(
          DesktopWindowAdapter.capabilities.supportsVideoPlayback,
          isFalse,
        );
        expect(
          DesktopWindowAdapter.capabilities.supportsWindowDocking,
          isFalse,
        );
      },
    );

    test('Supports custom adapter override for testing', () {
      final custom = MacosDesktopWindowPlatformAdapter();
      DesktopWindowAdapter.setAdapterForTesting(custom);
      expect(DesktopWindowAdapter.current, equals(custom));
    });
  });
}
