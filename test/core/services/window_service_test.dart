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
  bool get supportsMultipleWindows => true;

  @override
  bool get supportsNativeFilePaths => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
      expect(windowService.openWindows.length, 1);
      final record = windowService.openWindows.first;
      expect(record.targetId, 'chat:s1');
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
  });
}
