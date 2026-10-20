import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gotoim_flutter/core/browser/desktop_browser_window.dart';
import 'package:gotoim_flutter/core/config/app_environment.dart';
import 'package:gotoim_flutter/core/media/media_preview.dart';
import 'package:gotoim_flutter/core/services/tray_grouped_unread_provider.dart';
import 'package:gotoim_flutter/core/services/tray_message_models.dart';
import 'package:gotoim_flutter/core/widgets/desktop_tray_message_box.dart';
import 'package:gotoim_flutter/features/media/presentation/desktop_media_viewer_window.dart';
import 'package:gotoim_flutter/features/settings/presentation/desktop_settings_window.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:gotoim_flutter/core/device/client_device_context.dart';
import 'package:gotoim_flutter/core/network/abp/abp_current_user.dart';
import 'package:gotoim_flutter/features/auth/application/auth_controller.dart';
import 'package:gotoim_flutter/features/session/application/session_list_controller.dart';
import 'package:gotoim_flutter/features/session/data/models/chat_owner.dart';
import 'package:gotoim_flutter/features/session/data/models/session_summary.dart';

const _fakeDevice = ClientDeviceContext(
  appId: 'gotoim-desktop',
  appName: 'GotoIM',
  appVersion: '1.0.0',
  deviceId: 'desktop-win-001',
  deviceType: 'windows',
  platform: 'Windows',
  brand: 'PC',
  model: 'Desktop',
  browser: 'FlutterEngine',
  pushClientId: 'none',
);

class _MockSessionListController extends ChangeNotifier
    implements SessionListController {
  @override
  List<SessionSummary> get sessions => const [];

  @override
  ChatOwner? get currentOwner => const ChatOwner(
    id: 1001,
    name: '张三',
    imageUrl: null,
    typeDescription: '用户',
    unreadCount: 5,
  );

  @override
  int? get currentOwnerId => 1001;

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

class _SampleTrayGroupedUnreadNotifier extends TrayGroupedUnreadNotifier {
  @override
  TrayGroupedUnreadState build() {
    return TrayGroupedUnreadNotifier.createSampleState();
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => null,
        );
    dotenv.loadFromString(
      envString: 'APP_NAME=GotoIM\nAPI_BASE_URL=https://api.gotoim.com',
    );

    // 挂载真实系统字体与图标字体
    try {
      const fontPath = r'C:\Windows\Fonts\msyh.ttc';
      if (File(fontPath).existsSync()) {
        final fontData = File(fontPath).readAsBytesSync();
        final fontLoader = FontLoader('Microsoft YaHei')
          ..addFont(Future.value(ByteData.view(fontData.buffer)));
        await fontLoader.load();
      }
    } catch (_) {}

    try {
      final materialIconsFile = File(
        r'C:\Users\ZP\AppData\Local\Pub\Cache\hosted\pub.flutter-io.cn\material_design_icons_flutter-7.0.7296\lib\fonts\materialdesignicons-webfont.ttf',
      );
      if (materialIconsFile.existsSync()) {
        final iconData = materialIconsFile.readAsBytesSync();
        final iconLoader = FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.view(iconData.buffer)));
        await iconLoader.load();
      }
    } catch (_) {}
  });

  group('桌面端托盘未读数据模型与状态流转测试', () {
    test('初始状态默认为空状态，loadSampleData 后包含按聊天对象分组的未读数据', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final initialState = container.read(trayGroupedUnreadProvider);
      expect(initialState.totalUnread, equals(0));
      expect(initialState.groups, isEmpty);

      container.read(trayGroupedUnreadProvider.notifier).loadSampleData();
      final state = container.read(trayGroupedUnreadProvider);

      expect(state.totalUnread, equals(7));
      expect(state.groups.length, equals(2));

      // 一级分组 1: 张三 (当前身份，5 条新消息)
      final group1 = state.groups.first;
      expect(group1.ownerName, equals('张三'));
      expect(group1.isCurrent, isTrue);
      expect(group1.totalUnread, equals(5));
      expect(group1.sessions.length, equals(2));
      expect(group1.sessions[0].targetName, contains('李四'));
      expect(group1.sessions[0].unreadCount, equals(3));
      expect(group1.sessions[1].targetName, contains('桌面端跨平台架构组'));
      expect(group1.sessions[1].unreadCount, equals(2));

      // 一级分组 2: 客服身份 (2 条新消息)
      final group2 = state.groups[1];
      expect(group2.ownerName, contains('客服'));
      expect(group2.totalUnread, equals(2));
      expect(group2.sessions.length, equals(1));
    });

    test('标记单会话已读后自动更新该分组及总未读数', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(trayGroupedUnreadProvider.notifier);
      notifier.loadSampleData();

      // 标记会话 u-101 已读 (李四的 3 条消息)
      notifier.markSessionRead(1001, 'u-101');

      final state = container.read(trayGroupedUnreadProvider);
      expect(state.totalUnread, equals(4)); // 7 - 3 = 4

      final group1 = state.groups.firstWhere((g) => g.ownerId == 1001);
      expect(group1.totalUnread, equals(2)); // 5 - 3 = 2
      expect(group1.sessions.length, equals(1));
    });

    test('一键全部已读正确清空分组与总数', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(trayGroupedUnreadProvider.notifier);
      notifier.loadSampleData();
      notifier.markAllRead();

      final state = container.read(trayGroupedUnreadProvider);
      expect(state.totalUnread, equals(0));
      expect(state.groups, isEmpty);
    });

    test('模拟接收新消息时正确累加', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(trayGroupedUnreadProvider.notifier);
      notifier.loadSampleData();
      notifier.simulateIncomingMessage(
        ownerId: 1001,
        ownerName: '张三',
        sessionUnitId: 'u-101',
        targetName: '李四 (前端研发)',
        message: '新消息推送测试',
      );

      final state = container.read(trayGroupedUnreadProvider);
      expect(state.totalUnread, equals(8));
      final group1 = state.groups.firstWhere((g) => g.ownerId == 1001);
      expect(group1.totalUnread, equals(6));
    });
  });

  group('桌面端微信风格无边框窗口 (Frameless) 规范测试', () {
    testWidgets('DesktopTrayMessageBox 渲染无边框且层级清晰', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trayGroupedUnreadProvider.overrideWith(
              _SampleTrayGroupedUnreadNotifier.new,
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              backgroundColor: Color(0xFF1E1E1E),
              body: Center(child: DesktopTrayMessageBox()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证未读消息提醒标题与未读总数 Badge
      expect(find.text('未读消息提醒'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);

      // 验证一级分组：聊天对象 1 包含头像与 5 条新消息
      expect(find.text('张三'), findsOneWidget);
      expect(find.text('当前身份'), findsOneWidget);
      expect(find.text('5 条新消息'), findsOneWidget);

      // 验证二级好友会话
      expect(find.text('李四 (前端研发)'), findsOneWidget);
      expect(find.text('桌面端跨平台架构组 (4人)'), findsNothing); // 文本完整匹配部分
      expect(find.byType(DesktopTrayMessageBox), findsOneWidget);

      // 查找根容器，确认 border 为 null (微信同款无边框)
      final containerWidgets = tester.widgetList<Container>(
        find.byType(Container),
      );
      final flyoutContainer = containerWidgets.firstWhere(
        (c) =>
            c.decoration is BoxDecoration &&
            (c.decoration as BoxDecoration).boxShadow != null,
      );
      final decoration = flyoutContainer.decoration as BoxDecoration;
      expect(decoration.border, isNull, reason: '托盘浮窗必须无边框');
    });

    testWidgets('DesktopSettingsWindow 渲染圆角倒角 (borderRadius == 12)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appEnvironmentProvider.overrideWithValue(
              AppEnvironment.fromDotEnv(AppFlavor.development),
            ),
            clientDeviceContextProvider.overrideWithValue(_fakeDevice),
            authControllerProvider.overrideWith((ref) => _MockAuthController()),
            sessionListControllerProvider.overrideWith(
              (ref) => _MockSessionListController(),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: DesktopSettingsWindow()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final containerWidgets = tester.widgetList<Container>(
        find.byType(Container),
      );
      final settingsContainer = containerWidgets.firstWhere(
        (c) =>
            c.constraints?.maxWidth == 730 ||
            (c.decoration is BoxDecoration &&
                (c.decoration as BoxDecoration).boxShadow != null),
      );
      final decoration = settingsContainer.decoration as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(12), reason: '设置窗口必须有12dp圆角倒角');
    });

    testWidgets('DesktopBrowserWindow 渲染无边框 (border == null)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: DesktopBrowserWindow(
                initialUrl: 'https://example.com',
                title: '测试浏览',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final animatedContainers = tester.widgetList<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      expect(animatedContainers.isNotEmpty, isTrue);
      final decoration = animatedContainers.first.decoration as BoxDecoration;
      expect(decoration.border, isNull, reason: '独立浏览器窗口必须无边框');
    });

    testWidgets('DesktopMediaViewerWindow 渲染无边框 (border == null)', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopMediaViewerWindow(
              items: [
                MediaPreviewItem(
                  id: 'test-1',
                  messageId: 'm1',
                  type: MediaPreviewType.image,
                  source: 'https://example.com/test.jpg',
                  heroTag: 'test-img',
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final animatedContainers = tester.widgetList<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      expect(animatedContainers.isNotEmpty, isTrue);
      final decoration = animatedContainers.first.decoration as BoxDecoration;
      expect(decoration.border, isNull, reason: '独立媒体查看窗口必须无边框');
    });
  });
}
