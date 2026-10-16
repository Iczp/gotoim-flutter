import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gotoim_flutter/core/browser/desktop_browser_window.dart';
import 'package:gotoim_flutter/core/config/app_environment.dart';
import 'package:gotoim_flutter/core/device/client_device_context.dart';
import 'package:gotoim_flutter/core/media/media_preview.dart';
import 'package:gotoim_flutter/core/network/abp/abp_current_user.dart';
import 'package:gotoim_flutter/core/platform/platform_facade.dart';
import 'package:gotoim_flutter/core/services/tray_service.dart';
import 'package:gotoim_flutter/core/services/window_messenger.dart';
import 'package:gotoim_flutter/core/services/window_service.dart';
import 'package:gotoim_flutter/features/auth/application/auth_controller.dart';
import 'package:gotoim_flutter/features/media/presentation/desktop_media_viewer_window.dart';
import 'package:gotoim_flutter/features/session/application/session_list_controller.dart';
import 'package:gotoim_flutter/features/session/data/models/chat_owner.dart';
import 'package:gotoim_flutter/features/session/data/models/session_summary.dart';
import 'package:gotoim_flutter/features/session/presentation/desktop_session_split_view.dart';
import 'package:gotoim_flutter/features/settings/presentation/desktop_settings_window.dart';

class _FakeDesktopPlatformFacade implements PlatformFacade {
  const _FakeDesktopPlatformFacade();

  @override
  PlatformKind get kind => PlatformKind.windows;

  @override
  bool get isWeb => false;

  @override
  bool get supportsMultipleWindows => true;

  @override
  bool get supportsNativeFilePaths => true;
}

class _MockSessionListController extends ChangeNotifier
    implements SessionListController {
  _MockSessionListController(this._sessions);

  final List<SessionSummary> _sessions;

  @override
  List<SessionSummary> get sessions => _sessions;

  @override
  ChatOwner? get currentOwner => const ChatOwner(
    id: 1001,
    name: 'GotoIM 架构师',
    imageUrl: null,
    typeDescription: '用户',
    unreadCount: 15,
  );

  @override
  int? get currentOwnerId => 1001;

  @override
  Future<void> initialize({bool forceRemote = false}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockAuthController extends ChangeNotifier implements AuthController {
  @override
  AuthStatus get status => AuthStatus.authenticated;

  @override
  AbpCurrentUser? get currentUser => const AbpCurrentUser(
    id: 'user-001',
    userName: 'arch_gotoim',
    name: 'GotoIM 架构师',
    email: 'arch@gotoim.com',
  );

  @override
  String? get accountName => 'arch_gotoim';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _testTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  fontFamily: 'Microsoft YaHei',
  fontFamilyFallback: const [
    'Microsoft YaHei',
    '微软雅黑',
    'PingFang SC',
    'Segoe UI',
    'sans-serif',
  ],
  splashFactory: NoSplash.splashFactory,
  colorScheme: const ColorScheme.dark(
    surface: Color(0xFF1E1E1E),
    onSurface: Color(0xFFF0F0F0),
    primary: Color(0xFF07C160),
    onPrimary: Colors.white,
    secondary: Color(0xFFA0A0A0),
    error: Color(0xFFFA5151),
  ),
  scaffoldBackgroundColor: const Color(0xFF1E1E1E),
);

final _sampleSessions = <SessionSummary>[
  SessionSummary(
    id: 's_pin_1',
    ownerId: 1001,
    score: 1000,
    title: '产品研发与架构重构攻坚组',
    preview: '李工：桌面端独立窗口（媒体、浏览器、设置）已全部通过自适应测试',
    updatedAt: DateTime.now().subtract(const Duration(minutes: 5)),
    unreadCount: 3,
    isPinned: true,
    raw: const {},
    ticks: 1000,
  ),
  SessionSummary(
    id: 's_pin_2',
    ownerId: 1001,
    score: 900,
    title: '微信桌面端 4.0 视觉专项',
    preview: '设计部：深色暗黑风格规范与圆角阴影已全部落地',
    updatedAt: DateTime.now().subtract(const Duration(minutes: 25)),
    unreadCount: 0,
    isPinned: true,
    raw: const {},
    ticks: 900,
  ),
  SessionSummary(
    id: 's_norm_1',
    ownerId: 1001,
    score: 800,
    title: '后端 ABP vNext 实时通信群',
    preview: 'SignalR 连接网关状态良好，各设备增量同步已就绪',
    updatedAt: DateTime.now().subtract(const Duration(hours: 1)),
    unreadCount: 12,
    isPinned: false,
    raw: const {},
    ticks: 800,
  ),
  SessionSummary(
    id: 's_norm_2',
    ownerId: 1001,
    score: 700,
    title: '桌面端托盘与多窗口测试群',
    preview: '系统托盘常驻与右键菜单项已全部校验完成',
    updatedAt: DateTime.now().subtract(const Duration(hours: 2)),
    unreadCount: 0,
    isPinned: false,
    raw: const {},
    ticks: 700,
  ),
];

Future<void> _captureToDisk({
  required GlobalKey key,
  required WidgetTester tester,
  required String filename,
}) async {
  await tester.runAsync(() async {
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary != null) {
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final bytes = byteData.buffer.asUint8List();
        final dir = Directory(
          r'C:\Users\ZP\.gemini\antigravity\brain\f3f5edfb-7920-4a04-b0bc-cda5b23e58ef\screenshots',
        );
        if (!dir.existsSync()) {
          dir.createSync(recursive: true);
        }
        final file = File('${dir.path}\\$filename');
        await file.writeAsBytes(bytes);
        debugPrint(
          '[Screenshot] Saved -> ${file.path} (${bytes.length} bytes)',
        );
      }
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => null,
        );
    dotenv.loadFromString(
      envString: 'APP_NAME=GotoIM\nAPI_BASE_URL=https://api.gotoim.com',
    );

    // 载入真实字体以消除测试截图中的 Ahem 方块 (□)
    try {
      final iconFontFile = File(
        r'E:\sdk\flutter-3.47.0-active\bin\cache\artifacts\material_fonts\materialicons-regular.otf',
      );
      if (iconFontFile.existsSync()) {
        final iconBytes = await iconFontFile.readAsBytes();
        final fontLoader = FontLoader('MaterialIcons');
        fontLoader.addFont(Future.value(ByteData.view(iconBytes.buffer)));
        await fontLoader.load();
      }
    } catch (_) {}

    try {
      final yaheiFontFile = File(r'C:\Windows\Fonts\msyh.ttc');
      if (yaheiFontFile.existsSync()) {
        final fontBytes = await yaheiFontFile.readAsBytes();
        final fontLoader = FontLoader('Microsoft YaHei');
        fontLoader.addFont(Future.value(ByteData.view(fontBytes.buffer)));
        await fontLoader.load();
      }
    } catch (_) {}
  });

  const fakeDevice = ClientDeviceContext(
    appId: 'gotoim-desktop',
    appName: 'GotoIM',
    appVersion: '1.0.0',
    deviceId: 'desktop-win-001',
    deviceType: 'windows',
    platform: 'Windows',
    brand: 'PC',
    model: 'Windows x64',
    browser: '',
    pushClientId: '',
  );

  group('桌面端综合测试与全功能截图输出', () {
    test('1. 系统托盘服务 (DesktopTrayService) 状态与未读数管理测试', () async {
      final windowService = DefaultWindowService(
        platformFacade: const _FakeDesktopPlatformFacade(),
      );
      final trayService = DesktopTrayService(windowService: windowService);

      expect(trayService.isSupported, isTrue);

      await trayService.setUnread(5);
      await trayService.updateContextMenu(currentOwnerName: 'GotoIM 架构师');
      await trayService.dispose();
    });

    test('2. 桌面多窗口服务与跨窗口通讯 (WindowService & WindowMessenger)', () async {
      final windowService = DefaultWindowService(
        platformFacade: const _FakeDesktopPlatformFacade(),
      );
      final messenger = DefaultWindowMessenger();

      // 打开聊天
      await windowService.openChat(
        sessionUnitId: 's1',
        ownerId: 1001,
        title: '架构群',
      );
      expect(windowService.isWindowOpen('chat:s1'), isTrue);

      // 打开设置
      await windowService.openSettings();
      expect(windowService.isWindowOpen('tool:settings'), isTrue);

      // 打开网页
      await windowService.openWebBrowser(
        url: 'https://news.qq.com',
        title: '腾讯新闻',
      );
      expect(windowService.isWindowOpen('browser:https://news.qq.com'), isTrue);

      // 打开媒体查看器
      await windowService.openMediaViewer(
        mediaUrl: 'https://im.gotoim.com/image.png',
        items: [
          const MediaPreviewItem(
            id: 'm1',
            messageId: 'msg1',
            type: MediaPreviewType.image,
            source: 'https://im.gotoim.com/image.png',
            heroTag: 'hero1',
          ),
        ],
        initialIndex: 0,
      );
      expect(
        windowService.isWindowOpen('media:https://im.gotoim.com/image.png'),
        isTrue,
      );

      // 跨窗口广播测试
      var received = false;
      messenger.on('test:event', (data) => received = true);
      messenger.emit('test:event', {'ok': true});
      expect(received, isTrue);
    });

    testWidgets('3. 桌面端标准三栏布局 (1280x800) 渲染与分栏拖拽截图', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repaintKey = GlobalKey();
      final controller = _MockSessionListController(_sampleSessions);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appEnvironmentProvider.overrideWithValue(
              AppEnvironment.fromDotEnv(AppFlavor.development),
            ),
            clientDeviceContextProvider.overrideWithValue(fakeDevice),
            sessionListControllerProvider.overrideWith((ref) => controller),
          ],
          child: MaterialApp(
            theme: _testTheme,
            home: RepaintBoundary(
              key: repaintKey,
              child: Scaffold(
                body: Row(
                  children: [
                    // Dock Rail 仿真 (宽度 52, 头像居底)
                    Container(
                      width: 52,
                      color: const Color(0xFF1E1E1E),
                      child: Column(
                        children: [
                          const SizedBox(height: 16),
                          IconButton(
                            icon: const Badge(
                              label: Text('15'),
                              child: Icon(
                                Icons.chat_bubble_rounded,
                                color: Color(0xFF07C160),
                              ),
                            ),
                            onPressed: () {},
                          ),
                          const SizedBox(height: 12),
                          IconButton(
                            icon: const Icon(
                              Icons.people_alt_outlined,
                              color: Colors.white60,
                            ),
                            onPressed: () {},
                          ),
                          const SizedBox(height: 12),
                          IconButton(
                            icon: const Icon(
                              Icons.grid_view_rounded,
                              color: Colors.white60,
                            ),
                            onPressed: () {},
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(
                              Icons.settings_outlined,
                              color: Colors.white60,
                            ),
                            onPressed: () {},
                          ),
                          const SizedBox(height: 12),
                          const CircleAvatar(
                            radius: 17,
                            backgroundColor: Color(0xFF07C160),
                            child: Icon(
                              Icons.person,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                    const VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: Color(0x1FFFFFFF),
                    ),
                    // 会话分栏主视图
                    Expanded(
                      child: DesktopSessionSplitView(controller: controller),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('后端 ABP vNext 实时通信群'), findsOneWidget);
      expect(find.text('折叠置顶聊天 (2)'), findsOneWidget);
      expect(find.text('Goto IM 桌面端'), findsOneWidget);

      // 点击展开折叠置顶聊天
      await tester.tap(find.text('折叠置顶聊天 (2)'));
      await tester.pumpAndSettle();

      expect(find.text('产品研发与架构重构攻坚组'), findsOneWidget);
      expect(find.text('微信桌面端 4.0 视觉专项'), findsOneWidget);

      await _captureToDisk(
        key: repaintKey,
        tester: tester,
        filename: 'screenshot_desktop_wide_1280x800.png',
      );
    });

    testWidgets('4. 平板端双栏紧凑布局 (900x700) 渲染截图', (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repaintKey = GlobalKey();
      final controller = _MockSessionListController(_sampleSessions);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appEnvironmentProvider.overrideWithValue(
              AppEnvironment.fromDotEnv(AppFlavor.development),
            ),
            clientDeviceContextProvider.overrideWithValue(fakeDevice),
            sessionListControllerProvider.overrideWith((ref) => controller),
          ],
          child: MaterialApp(
            theme: _testTheme,
            home: RepaintBoundary(
              key: repaintKey,
              child: Scaffold(
                body: Row(
                  children: [
                    // 平板端常驻 Dock Rail 侧边栏 (宽度 52, 头像居底)
                    Container(
                      width: 52,
                      color: const Color(0xFF1E1E1E),
                      child: Column(
                        children: [
                          const SizedBox(height: 16),
                          IconButton(
                            icon: const Badge(
                              label: Text('15'),
                              child: Icon(
                                Icons.chat_bubble_rounded,
                                color: Color(0xFF07C160),
                              ),
                            ),
                            onPressed: () {},
                          ),
                          const SizedBox(height: 12),
                          IconButton(
                            icon: const Icon(
                              Icons.people_alt_outlined,
                              color: Colors.white60,
                            ),
                            onPressed: () {},
                          ),
                          const SizedBox(height: 12),
                          IconButton(
                            icon: const Icon(
                              Icons.grid_view_rounded,
                              color: Colors.white60,
                            ),
                            onPressed: () {},
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(
                              Icons.settings_outlined,
                              color: Colors.white60,
                            ),
                            onPressed: () {},
                          ),
                          const SizedBox(height: 12),
                          const CircleAvatar(
                            radius: 17,
                            backgroundColor: Color(0xFF07C160),
                            child: Icon(
                              Icons.person,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                    const VerticalDivider(
                      width: 1,
                      thickness: 0.5,
                      color: Color(0x1FFFFFFF),
                    ),
                    Expanded(
                      child: DesktopSessionSplitView(controller: controller),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('后端 ABP vNext 实时通信群'), findsOneWidget);
      await tester.tap(find.text('折叠置顶聊天 (2)'));
      await tester.pumpAndSettle();
      expect(find.text('产品研发与架构重构攻坚组'), findsOneWidget);

      await _captureToDisk(
        key: repaintKey,
        tester: tester,
        filename: 'screenshot_desktop_tablet_900x700.png',
      );
    });

    testWidgets('5. 手机/窄屏模式自适应布局 (450x800) 渲染截图', (tester) async {
      tester.view.physicalSize = const Size(450, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repaintKey = GlobalKey();
      final controller = _MockSessionListController(_sampleSessions);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appEnvironmentProvider.overrideWithValue(
              AppEnvironment.fromDotEnv(AppFlavor.development),
            ),
            clientDeviceContextProvider.overrideWithValue(fakeDevice),
            sessionListControllerProvider.overrideWith((ref) => controller),
          ],
          child: MaterialApp(
            theme: _testTheme,
            home: RepaintBoundary(
              key: repaintKey,
              child: Scaffold(
                body: DesktopSessionSplitView(controller: controller),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('后端 ABP vNext 实时通信群'), findsOneWidget);
      await tester.tap(find.text('折叠置顶聊天 (2)'));
      await tester.pumpAndSettle();
      expect(find.text('产品研发与架构重构攻坚组'), findsOneWidget);

      await _captureToDisk(
        key: repaintKey,
        tester: tester,
        filename: 'screenshot_desktop_phone_450x800.png',
      );
    });

    testWidgets('6. 微信同款独立设置窗口 (DesktopSettingsWindow - 730x560) 渲染与各标签页测试截图', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(730, 560);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repaintKey = GlobalKey();
      final controller = _MockSessionListController(_sampleSessions);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appEnvironmentProvider.overrideWithValue(
              AppEnvironment.fromDotEnv(AppFlavor.development),
            ),
            clientDeviceContextProvider.overrideWithValue(fakeDevice),
            sessionListControllerProvider.overrideWith((ref) => controller),
            authControllerProvider.overrideWith((ref) => _MockAuthController()),
          ],
          child: MaterialApp(
            theme: _testTheme,
            home: RepaintBoundary(
              key: repaintKey,
              child: const Scaffold(body: DesktopSettingsWindow()),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('设置'), findsOneWidget);
      expect(find.text('账号与存储'), findsOneWidget);
      expect(find.text('通用'), findsOneWidget);
      expect(find.text('快捷键'), findsOneWidget);
      expect(find.text('通知'), findsOneWidget);
      expect(find.text('插件'), findsOneWidget);
      expect(find.text('关于 GotoIM'), findsOneWidget);

      await _captureToDisk(
        key: repaintKey,
        tester: tester,
        filename: 'screenshot_desktop_settings_window.png',
      );
    });

    testWidgets('7. 微信同款独立网页浏览器窗口 (DesktopBrowserWindow - 1000x700) 渲染截图', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repaintKey = GlobalKey();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appEnvironmentProvider.overrideWithValue(
              AppEnvironment.fromDotEnv(AppFlavor.development),
            ),
            clientDeviceContextProvider.overrideWithValue(fakeDevice),
          ],
          child: MaterialApp(
            theme: _testTheme,
            home: RepaintBoundary(
              key: repaintKey,
              child: const Scaffold(
                body: DesktopBrowserWindow(
                  initialUrl: 'https://news.qq.com',
                  title: '腾讯新闻 - 全球最新资讯实时更新',
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('腾讯新闻 - 全球最新资讯实时更新'), findsWidgets);
      expect(find.byIcon(Icons.arrow_back_ios_rounded), findsOneWidget);
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
      expect(find.byIcon(Icons.open_in_browser_rounded), findsOneWidget);

      await _captureToDisk(
        key: repaintKey,
        tester: tester,
        filename: 'screenshot_desktop_browser_window.png',
      );
    });

    testWidgets(
      '8. 微信同款独立媒体查看窗口 (DesktopMediaViewerWindow - 920x680) 渲染与工具栏测试截图',
      (tester) async {
        tester.view.physicalSize = const Size(920, 680);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final repaintKey = GlobalKey();
        final items = [
          const MediaPreviewItem(
            id: 'test_img_1',
            messageId: 'msg_01',
            type: MediaPreviewType.image,
            source: 'assets/images/splash_logo.png',
            heroTag: 'hero_test_1',
            fileName: 'GotoIM_Architecture.png',
          ),
          const MediaPreviewItem(
            id: 'test_img_2',
            messageId: 'msg_02',
            type: MediaPreviewType.image,
            source: 'assets/images/app_icon.ico',
            heroTag: 'hero_test_2',
            fileName: 'AppIcon.ico',
          ),
        ];

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appEnvironmentProvider.overrideWithValue(
                AppEnvironment.fromDotEnv(AppFlavor.development),
              ),
              clientDeviceContextProvider.overrideWithValue(fakeDevice),
            ],
            child: MaterialApp(
              theme: _testTheme,
              home: RepaintBoundary(
                key: repaintKey,
                child: Scaffold(
                  body: DesktopMediaViewerWindow(items: items, initialIndex: 0),
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.zoom_in_rounded), findsOneWidget);
        expect(find.byIcon(Icons.zoom_out_rounded), findsOneWidget);
        expect(find.byIcon(Icons.rotate_right_rounded), findsOneWidget);
        expect(find.byIcon(Icons.save_alt_rounded), findsOneWidget);
        expect(find.text('1 / 2'), findsOneWidget);

        await _captureToDisk(
          key: repaintKey,
          tester: tester,
          filename: 'screenshot_desktop_media_viewer_window.png',
        );
      },
    );

    testWidgets('9. 系统托盘图标、未读提醒与右键上下文菜单模拟渲染截图 (360x300)', (tester) async {
      tester.view.physicalSize = const Size(360, 300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repaintKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          theme: _testTheme,
          home: RepaintBoundary(
            key: repaintKey,
            child: Scaffold(
              backgroundColor: const Color(0xFF141414),
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 模拟任务栏托盘区域
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF202020),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0x2FFFFFFF)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.wifi,
                            size: 16,
                            color: Colors.white70,
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.volume_up,
                            size: 16,
                            color: Colors.white70,
                          ),
                          const SizedBox(width: 12),
                          // GotoIM 托盘图标（带未读红点角标）
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2C2C2C),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                const Icon(
                                  Icons.chat_bubble_rounded,
                                  color: Color(0xFF07C160),
                                  size: 18,
                                ),
                                Positioned(
                                  top: -4,
                                  right: -6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 3,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFA5151),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      '5',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            '19:50',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    // 模拟右键弹出的上下文菜单 (ContextMenu)
                    Container(
                      width: 220,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2B2B2B),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0x3FFFFFFF)),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black45,
                            blurRadius: 16,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildMenuItem(
                            '显示 Goto IM',
                            Icons.open_in_new_rounded,
                            true,
                          ),
                          const Divider(
                            height: 1,
                            thickness: 0.5,
                            color: Color(0x1FFFFFFF),
                          ),
                          _buildMenuItem(
                            '当前身份: GotoIM 架构师',
                            Icons.account_circle_outlined,
                            false,
                          ),
                          _buildMenuItem(
                            '未读消息: 5 条',
                            Icons.mark_chat_unread_outlined,
                            false,
                          ),
                          const Divider(
                            height: 1,
                            thickness: 0.5,
                            color: Color(0x1FFFFFFF),
                          ),
                          _buildMenuItem(
                            '退出应用',
                            Icons.power_settings_new_rounded,
                            true,
                            isDestructive: true,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('显示 Goto IM'), findsOneWidget);
      expect(find.text('当前身份: GotoIM 架构师'), findsOneWidget);
      expect(find.text('未读消息: 5 条'), findsOneWidget);
      expect(find.text('退出应用'), findsOneWidget);

      await _captureToDisk(
        key: repaintKey,
        tester: tester,
        filename: 'screenshot_desktop_tray_menu.png',
      );
    });
  });
}

Widget _buildMenuItem(
  String title,
  IconData icon,
  bool enabled, {
  bool isDestructive = false,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Row(
      children: [
        Icon(
          icon,
          size: 15,
          color:
              isDestructive
                  ? const Color(0xFFFA5151)
                  : (enabled ? Colors.white : Colors.white38),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color:
                  isDestructive
                      ? const Color(0xFFFA5151)
                      : (enabled ? Colors.white : Colors.white38),
              fontWeight: isDestructive ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ],
    ),
  );
}
