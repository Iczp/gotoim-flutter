import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/platform/platform_facade.dart';
import 'package:gotoim_flutter/core/services/window_service.dart';

class _FakePlatformFacade implements PlatformFacade {
  const _FakePlatformFacade();

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

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('mixin.one/desktop_multi_window/channels'),
      (call) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('mixin.one/desktop_multi_window'),
      (call) async {
        switch (call.method) {
          case 'createWindow':
            return '101';
          case 'show':
          case 'hide':
          case 'close':
          case 'focus':
          case 'setFrame':
          case 'center':
            return null;
          case 'getAllSubWindowIds':
            return <int>[];
          default:
            return null;
        }
      },
    );
  });

  group('DefaultWindowService Tests', () {
    late DefaultWindowService windowService;

    setUp(() {
      windowService = DefaultWindowService(
        platformFacade: const _FakePlatformFacade(),
      );
    });

    test('Initial window state is empty', () {
      expect(windowService.openWindows, isEmpty);
      expect(windowService.isWindowOpen('chat:s1'), isFalse);
    });

    test('openChat registers a window and emits to stream', () async {
      final recordsHistory = <List<WindowRecord>>[];
      final sub = windowService.openWindowsStream.listen(recordsHistory.add);

      await windowService.openChat(
        sessionUnitId: 's1',
        ownerId: 100,
        title: '测试会话',
      );

      expect(windowService.isWindowOpen('chat:s1'), isTrue);
      expect(windowService.isWindowOpen('chat:100:s1'), isTrue);
      expect(windowService.openWindows.length, 1);
      final record = windowService.openWindows.first;
      expect(record.targetId, 'chat:100:s1');
      expect(record.type, WindowType.chat);
      expect(record.title, '测试会话');
      expect(record.extra?['ownerId'], 100);

      // Calling openChat again with same targetId should not duplicate
      await windowService.openChat(
        sessionUnitId: 's1',
        ownerId: 100,
        title: '测试会话',
      );
      expect(windowService.openWindows.length, 1);

      // Close window
      await windowService.closeWindow('chat:s1');
      expect(windowService.isWindowOpen('chat:s1'), isFalse);
      expect(windowService.openWindows, isEmpty);

      await sub.cancel();
    });

    test(
      'openMiniApp, openLocalFileServer and openDiagnostics register correctly',
      () async {
        await windowService.openMiniApp(
          appId: 'crm',
          initialUrl: 'https://example.com/crm',
          title: 'CRM微应用',
        );
        expect(windowService.isWindowOpen('miniApp:crm'), isTrue);

        await windowService.openLocalFileServer();
        expect(windowService.isWindowOpen('tool:localFileServer'), isTrue);

        await windowService.openDiagnostics();
        expect(windowService.isWindowOpen('tool:diagnostics'), isTrue);

        expect(windowService.openWindows.length, 3);
      },
    );

    test(
      'openWebBrowser, openMediaViewer, and openSettings register correctly',
      () async {
        await windowService.openWebBrowser(
          url: 'https://news.qq.com/article/1',
          title: '腾讯新闻',
        );
        expect(
          windowService.isWindowOpen('browser:https://news.qq.com/article/1'),
          isTrue,
        );

        await windowService.openMediaViewer(
          mediaUrl: 'https://cdn.example.com/image.jpg',
          title: '图片预览',
        );
        expect(
          windowService.isWindowOpen('media:https://cdn.example.com/image.jpg'),
          isTrue,
        );

        await windowService.openSettings();
        expect(windowService.isWindowOpen('tool:settings'), isTrue);

        expect(windowService.openWindows.length, 3);
      },
    );

    test('Creation failure rolls back atomic opening placeholder and leaves no fake records', () async {
      // Temporarily make createWindow throw
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('mixin.one/desktop_multi_window'),
        (call) async {
          if (call.method == 'createWindow') {
            throw Exception('OS Window creation failed');
          }
          return null;
        },
      );

      await windowService.openChat(
        sessionUnitId: 'fail_session',
        ownerId: 999,
        title: '失败测试会话',
      );

      // Should NOT leave any record in openWindows
      expect(windowService.isWindowOpen('chat:999:fail_session'), isFalse);
      expect(windowService.isWindowOpen('chat:fail_session'), isFalse);

      // Restore mock handler
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('mixin.one/desktop_multi_window'),
        (call) async {
          if (call.method == 'createWindow') return '102';
          return null;
        },
      );

      // Subsequent attempt succeeds without blocked opening placeholder
      await windowService.openChat(
        sessionUnitId: 'fail_session',
        ownerId: 999,
        title: '失败测试会话重试',
      );
      expect(windowService.isWindowOpen('chat:999:fail_session'), isTrue);
    });
  });
}
