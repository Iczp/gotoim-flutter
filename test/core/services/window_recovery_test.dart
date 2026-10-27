import 'dart:async';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/platform/platform_facade.dart';
import 'package:gotoim_flutter/core/services/window_service.dart';

class _Desktop implements PlatformFacade {
  @override
  PlatformKind get kind => PlatformKind.windows;
  @override
  bool get isWeb => false;
  @override
  bool get isDesktop => true;
  @override
  bool get supportsMultipleWindows => true;
  @override
  bool get supportsNativeFilePaths => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  var created = 0;
  final live = <String>{};
  final calls = <String>[];
  var rejectAddTab = false;

  setUp(() {
    created = 0;
    live.clear();
    calls.clear();
    rejectAddTab = false;
    messenger.setMockMethodCallHandler(
      const MethodChannel('mixin.one/desktop_multi_window'),
      (call) async {
        if (call.method == 'createWindow') {
          final id = 'window-${++created}';
          live.add(id);
          return id;
        }
        if (call.method == 'getAllWindows') {
          return [
            for (final id in live) {'windowId': id, 'windowArgument': ''},
          ];
        }
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('mixin.one/desktop_multi_window/channels'),
      (call) async {
        if (call.method != 'invokeMethod') return null;
        final args = call.arguments as Map;
        final method = args['method'] as String;
        final id = (args['channel'] as String).split('/').last;
        calls.add('$id:$method');
        if (!live.contains(id)) {
          throw PlatformException(code: 'CHANNEL_UNREGISTERED');
        }
        if (method == 'browser_add_tab' && rejectAddTab) {
          throw TimeoutException('renderer busy');
        }
        return true;
      },
    );
  });

  test('closed browser is replaced once and live browser is reused', () async {
    final service = DefaultWindowService(platformFacade: _Desktop());
    await service.openWebBrowser(url: 'https://first.test');
    expect(created, 1);
    live.remove('window-1');
    await service.openWebBrowser(url: 'https://second.test');
    expect(created, 2);
    expect(calls, isNot(contains('window-1:browser_add_tab')));
    await service.openWebBrowser(url: 'https://third.test');
    expect(created, 2);
    expect(calls, contains('window-2:browser_add_tab'));
  });

  test('timeout on a live browser never creates another WebView', () async {
    final service = DefaultWindowService(platformFacade: _Desktop());
    await service.openWebBrowser(url: 'https://first.test');
    rejectAddTab = true;
    await expectLater(
      service.openWebBrowser(url: 'https://second.test'),
      throwsA(
        isA<WindowChannelException>().having(
          (error) => error.toString(),
          'underlying timeout',
          contains('renderer busy'),
        ),
      ),
    );
    expect(created, 1);
    expect(service.isWindowOpen('tool:browser'), isTrue);
    rejectAddTab = false;
    await service.openWebBrowser(url: 'https://second.test');
    expect(created, 1);
  });

  test('failed activation removes confirmed dead browser state', () async {
    final service = DefaultWindowService(platformFacade: _Desktop());
    await service.openWebBrowser(url: 'https://first.test');
    live.clear();
    await service.bringToFront('tool:browser');
    expect(service.isWindowOpen('tool:browser'), isFalse);
    expect(service.hasWarmBrowserWindow, isFalse);
  });
}
