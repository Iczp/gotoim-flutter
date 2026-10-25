import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/platform/desktop_window_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('gotoim/window');
  final calls = <MethodCall>[];
  bool fail = false;
  setUp(() {
    calls.clear();
    fail = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (fail) throw PlatformException(code: 'WINDOW_UNAVAILABLE');
          return call.method == 'toggleMaximize';
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    DesktopWindowAdapter.onCloseRequested = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    channel.setMethodCallHandler(null);
  });

  for (final target in [TargetPlatform.macOS, TargetPlatform.linux]) {
    test('$target dispatches controls and preserves size arguments', () async {
      debugDefaultTargetPlatformOverride = target;
      await DesktopWindowAdapter.setupCustomTitleBar();
      expect(DesktopWindowAdapter.isMaximized(), isFalse);
      await DesktopWindowAdapter.toggleMaximize();
      expect(DesktopWindowAdapter.isMaximized(), isTrue);
      await DesktopWindowAdapter.center(width: 720, height: 480);
      expect(calls.last.method, 'center');
      expect(calls.last.arguments, {'width': 720, 'height': 480});
      fail = true;
      await expectLater(
        DesktopWindowAdapter.toggleMaximize(),
        throwsA(isA<PlatformException>()),
      );
      expect(DesktopWindowAdapter.isMaximized(), isTrue);
    });

    test(
      '$target refuses unsupported docking without native mutation',
      () async {
        debugDefaultTargetPlatformOverride = target;
        expect(
          await DesktopWindowAdapter.dockToParent(
            x: 1,
            y: 2,
            width: 400,
            height: 600,
          ),
          isFalse,
        );
        expect(calls, isEmpty);
        await expectLater(
          DesktopWindowAdapter.prepareFrame(),
          throwsA(isA<UnsupportedError>()),
        );
      },
    );

    test('$target receives close events on this engine channel', () async {
      debugDefaultTargetPlatformOverride = target;
      await DesktopWindowAdapter.setupCustomTitleBar();
      var closed = 0;
      DesktopWindowAdapter.onCloseRequested = () async {
        closed++;
      };
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            'gotoim/window',
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('closeRequested'),
            ),
            (_) {},
          );
      expect(closed, 1);
    });
  }
}
