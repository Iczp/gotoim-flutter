import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:gotoim_flutter/core/services/tray_badge_generator.dart';
import 'package:gotoim_flutter/core/browser/desktop_browser_window.dart';
import 'package:gotoim_flutter/core/native_window/desktop_window_title_bar.dart';
import 'package:gotoim_flutter/core/platform/windows/windows_window_adapter.dart';
import 'package:gotoim_flutter/core/services/tray_message_models.dart';
import 'package:gotoim_flutter/core/services/tray_service.dart';
import 'package:gotoim_flutter/core/services/window_service.dart';
import 'package:gotoim_flutter/core/platform/platform_facade.dart';
import 'package:gotoim_flutter/features/chat/data/models/chat_message.dart';

class _BadgePaths extends PathProviderPlatform {
  _BadgePaths(this.path);
  final String path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final commands = <String>[];
  var maximized = false;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    commands.clear();
    maximized = false;
    messenger.setMockMethodCallHandler(const MethodChannel('gotoim/window'), (
      call,
    ) async {
      commands.add(call.method);
      if (call.method == 'toggleMaximize') maximized = !maximized;
      return maximized;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    WindowsWindowAdapter.onCloseRequested = null;
    messenger.setMockMethodCallHandler(
      const MethodChannel('gotoim/window'),
      null,
    );
  });

  test(
    'window commands use the per-engine platform channel and restore explicitly',
    () async {
      await WindowsWindowAdapter.setupCustomTitleBar();
      await WindowsWindowAdapter.minimize();
      await WindowsWindowAdapter.bringToFront();
      await WindowsWindowAdapter.toggleMaximize();
      expect(WindowsWindowAdapter.isMaximized(), isTrue);
      await WindowsWindowAdapter.close();
      expect(commands, [
        'configure',
        'minimize',
        'restore',
        'toggleMaximize',
        'close',
      ]);
    },
  );

  test(
    'Windows tray uses the platform thread and reports native failures',
    () async {
      await WindowsWindowAdapter.initializeTray();
      await WindowsWindowAdapter.updateTray({'unread': 5});
      await WindowsWindowAdapter.showTrayMenu();
      await WindowsWindowAdapter.destroyTray();
      expect(commands, [
        'trayInitialize',
        'trayUpdate',
        'trayMenu',
        'trayDestroy',
      ]);
      messenger.setMockMethodCallHandler(const MethodChannel('gotoim/window'), (
        _,
      ) async {
        throw PlatformException(code: 'TRAY_UPDATE_FAILED');
      });
      await expectLater(
        WindowsWindowAdapter.updateTray({'unread': 6}),
        throwsA(isA<PlatformException>()),
      );
    },
  );

  testWidgets(
    'concurrent badge generation completes, caches and produces Windows ICO',
    (tester) async {
      await tester.runAsync(() async {
        final original = PathProviderPlatform.instance;
        final directory = await Directory.systemTemp.createTemp(
          'gotoim-badge-test-',
        );
        PathProviderPlatform.instance = _BadgePaths(directory.path);
        try {
          final first = TrayBadgeGenerator.generateBadgeIconPath(
            unreadCount: 57,
          );
          final second = TrayBadgeGenerator.generateBadgeIconPath(
            unreadCount: 57,
          );
          expect(identical(first, second), isTrue);
          final results = await Future.wait([
            first,
            second,
          ]).timeout(const Duration(seconds: 10));
          expect(results.first, isNotNull);
          expect(results.first, endsWith(Platform.isWindows ? '.ico' : '.png'));
          final bytes = await File(results.first!).readAsBytes();
          if (Platform.isWindows) {
            expect(bytes.take(6).toList(), [0, 0, 1, 0, 1, 0]);
          }
          expect(
            await TrayBadgeGenerator.generateBadgeIconPath(unreadCount: 57),
            results.first,
          );
        } finally {
          PathProviderPlatform.instance = original;
          await directory.delete(recursive: true);
        }
      });
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'browser custom close invokes its lifecycle callback once without native destroy',
    (tester) async {
      var closed = 0;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: DesktopBrowserWindow(
              initialUrl: 'https://example.com',
              isSubWindow: true,
              onClose: () => closed++,
            ),
          ),
        ),
      );
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pump();
      // On a wide window, a loose Flexible tab plus Spacer used to leave
      // unused space after the close control instead of aligning it right.
      expect(tester.getRect(find.byTooltip('关闭窗口')).right, greaterThan(1560));
      await tester.tap(find.byTooltip('关闭窗口'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(closed, 1);
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget.key?.toString().contains('close_browser_tab_') ?? false,
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));
      expect(closed, 2);
      expect(commands.where((c) => c == 'close' || c == 'destroy'), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('routed tool window chrome has a working tooltip overlay', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder:
            (_, child) => DesktopToolWindowFrame(
              title: '开发诊断中心',
              onClose: () {},
              child: child!,
            ),
        home: const Scaffold(body: Text('工具内容')),
      ),
    );
    expect(tester.takeException(), isNull);
    final tooltip = tester.state<RawTooltipState>(find.byTooltip('最小化'));
    tooltip.ensureTooltipVisible();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.text('最小化'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'main tray registers IPC commands without a reverse provider dependency',
    () {
      final service = DefaultWindowService(
        platformFacade: createPlatformFacade(),
        isSubWindow: true,
      );
      final container = ProviderContainer(
        overrides: [windowServiceProvider.overrideWithValue(service)],
      );
      final tray = container.read(trayServiceProvider);
      expect(tray, isA<DesktopTrayService>());
      expect(service.trayCommand, isNotNull);
      expect(container.read(windowServiceProvider), same(service));
      expect(container.read(trayServiceProvider), same(tray));
      container.dispose();
      expect(service.trayCommand, isNull);
    },
  );

  test('IPC snapshot preserves grouped real unread data', () {
    final state = TrayGroupedUnreadState(
      totalUnread: 3,
      groups: [
        TrayOwnerGroup(
          ownerId: 13,
          ownerName: '测试身份',
          totalUnread: 3,
          isCurrent: true,
          sessions: [
            TraySessionItem(
              sessionUnitId: 'session',
              targetName: '测试对象',
              lastMessageText: '摘要',
              unreadCount: 3,
              lastMessageTime: DateTime(2026, 10, 18),
            ),
          ],
        ),
      ],
    );
    final restored = TrayGroupedUnreadState.fromJson(state.toJson());
    expect(restored.toJson(), state.toJson());
  });

  test('message IPC preserves video payload, identity and cursor', () {
    final message = ChatMessage.fromJson(
      {
        'id': 789,
        'messageType': 4,
        'senderSessionUnitId': 'session',
        'content': {'videoUrl': '/video.mp4', 'width': 1280, 'height': 720},
      },
      ownerId: 13,
      sessionUnitId: 'session',
    );
    final restored = ChatMessage.fromWindowPayload(message.toWindowPayload());
    expect(restored.mediaUrl, '/video.mp4');
    expect(restored.messageType, 4);
    expect(restored.score, message.score);
    expect(restored.ownerId, 13);
    expect(restored.isMine, true);
    expect(restored.raw, message.raw);
  });
}
