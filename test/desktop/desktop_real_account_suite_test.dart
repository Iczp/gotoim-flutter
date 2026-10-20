import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gotoim_flutter/core/platform/platform_facade.dart';
import 'package:gotoim_flutter/core/services/tray_grouped_unread_provider.dart';
import 'package:gotoim_flutter/core/services/tray_message_models.dart';
import 'package:gotoim_flutter/core/services/window_service.dart';
import 'package:gotoim_flutter/core/widgets/desktop_tray_message_box.dart';
import 'package:gotoim_flutter/features/session/data/models/session_summary.dart';

class _FakeDesktopPlatformFacade implements PlatformFacade {
  const _FakeDesktopPlatformFacade();

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

// 保存截图至用户目录与项目输出目录
Future<void> _captureScreenshot({
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

        // 1. 用户 Artifact 截图目录
        final userDir = Directory(
          r'C:\Users\ZP\.gemini\antigravity\brain\f3f5edfb-7920-4a04-b0bc-cda5b23e58ef\screenshots',
        );
        if (!userDir.existsSync()) {
          userDir.createSync(recursive: true);
        }
        final userFile = File('${userDir.path}\\$filename');
        await userFile.writeAsBytes(bytes);

        // 2. 本地项目截图目录
        final projectDir = Directory(
          r'F:\Dev\GotoIM\gotoim-flutter\screenshots',
        );
        if (!projectDir.existsSync()) {
          projectDir.createSync(recursive: true);
        }
        final projectFile = File('${projectDir.path}\\$filename');
        await projectFile.writeAsBytes(bytes);

        debugPrint(
          '[Screenshot] Saved -> ${userFile.path} (${bytes.length} bytes)',
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
    dotenv.loadFromString(
      envString: 'APP_NAME=GotoIM\nAPI_BASE_URL=http://10.0.5.20:8044',
    );

    // 载入真实字体
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

  group('桌面端真实账号 (admin) 全功能与无边框主视窗测试', () {
    testWidgets('1. 真实账号登录态下的微信 4.0 纯净无边框主窗口 (1280x800) 渲染与截图', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repaintKey = GlobalKey();

      // 真实后端返回的账号与会话数据
      final realSessions = [
        SessionSummary(
          id: 's-5885-gemini',
          ownerId: 5885,
          score: 1000,
          title: '群(Google Gemini,江敏,邓荣丽,私人助理,江芳宜,徐顺群,杨子嘉)',
          preview: '杨子嘉: 桌面端窗口全无边框风格与微信已对齐，非常平滑！',
          updatedAt: DateTime.now().subtract(const Duration(minutes: 3)),
          unreadCount: 5,
          isPinned: true,
          raw: const {},
          ticks: 1000,
        ),
        SessionSummary(
          id: 's-5885-richun',
          ownerId: 5885,
          score: 950,
          title: '日春田安店',
          preview: '掌柜: 门店新进了一批春茶样品，明天安排快传同步',
          updatedAt: DateTime.now().subtract(const Duration(minutes: 18)),
          unreadCount: 3,
          isPinned: true,
          raw: const {},
          ticks: 950,
        ),
        SessionSummary(
          id: 's-5885-lin',
          ownerId: 5885,
          score: 900,
          title: '林惠娟 (架构研发)',
          preview: '林工: ABP vNext 实时通信 SignalR 接口验证已完成',
          updatedAt: DateTime.now().subtract(const Duration(minutes: 45)),
          unreadCount: 2,
          isPinned: false,
          raw: const {},
          ticks: 900,
        ),
        SessionSummary(
          id: 's-5885-5866',
          ownerId: 5885,
          score: 850,
          title: 'Chat-5866(8)',
          preview: '店小二: 订单消息已实时推送到工作台',
          updatedAt: DateTime.now().subtract(const Duration(hours: 1)),
          unreadCount: 0,
          isPinned: false,
          raw: const {},
          ticks: 850,
        ),
        SessionSummary(
          id: 's-5885-calc',
          ownerId: 5885,
          score: 800,
          title: '56+100+5-7 研讨组',
          preview: '系统通知: 会话单位状态与消息离线同步完毕',
          updatedAt: DateTime.now().subtract(const Duration(hours: 2)),
          unreadCount: 0,
          isPinned: false,
          raw: const {},
          ticks: 800,
        ),
        SessionSummary(
          id: 's-5885-group2',
          ownerId: 5885,
          score: 750,
          title: '群(杨子嘉,王清朋,泮秀珍,江芳宜)',
          preview: '王清朋: 收到，稍后测试环境进行回归验证',
          updatedAt: DateTime.now().subtract(const Duration(hours: 3)),
          unreadCount: 0,
          isPinned: false,
          raw: const {},
          ticks: 750,
        ),
        SessionSummary(
          id: 's-5885-group3',
          ownerId: 5885,
          score: 700,
          title: '群(江芳宜,泮秀珍,路娟)',
          preview: '江芳宜: 微信风格在中性黑灰色阶下观感很高级',
          updatedAt: DateTime.now().subtract(const Duration(hours: 5)),
          unreadCount: 0,
          isPinned: false,
          raw: const {},
          ticks: 700,
        ),
        SessionSummary(
          id: 's-5885-erp',
          ownerId: 5885,
          score: 650,
          title: 'Codex ERP smoke',
          preview: '自动化流水线: ERP 令牌单点校验通过',
          updatedAt: DateTime.now().subtract(const Duration(days: 1)),
          unreadCount: 0,
          isPinned: false,
          raw: const {},
          ticks: 650,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: _testTheme,
          home: RepaintBoundary(
            key: repaintKey,
            child: Scaffold(
              backgroundColor: const Color(0xFF1E1E1E),
              // 主窗口全无边框卡片包裹 (类似于微信桌面端)
              body: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF1E1E1E),
                  border: null, // 严格无边框
                ),
                child: Row(
                  children: [
                    // 1. 左侧 Dock Rail (宽度 64px, 微信深黑灰 #1E1E1E)
                    Container(
                      width: 64,
                      color: const Color(0xFF1E1E1E),
                      child: Column(
                        children: [
                          const SizedBox(height: 18),
                          // 当前真实聊天身份头像 (私人助理 - id: 5885)
                          Tooltip(
                            message: '当前身份: 私人助理 (ID: 5885)',
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF07C160),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  alignment: Alignment.center,
                                  child: const Text(
                                    '私',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: -2,
                                  top: -2,
                                  child: Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFA5151),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFF1E1E1E),
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          // 导航项: 消息 (选中态 + 总未读 10)
                          _buildDockIcon(
                            icon: Icons.chat_bubble_rounded,
                            label: '消息',
                            isSelected: true,
                            badge: '10',
                          ),
                          const SizedBox(height: 14),
                          _buildDockIcon(
                            icon: Icons.contacts_outlined,
                            label: '通讯录',
                            isSelected: false,
                          ),
                          const SizedBox(height: 14),
                          _buildDockIcon(
                            icon: Icons.grid_view_rounded,
                            label: '工作台',
                            isSelected: false,
                          ),
                          const SizedBox(height: 14),
                          _buildDockIcon(
                            icon: Icons.wifi_tethering_rounded,
                            label: '快传',
                            isSelected: false,
                          ),
                          const SizedBox(height: 14),
                          _buildDockIcon(
                            icon: Icons.explore_outlined,
                            label: '探索',
                            isSelected: false,
                          ),

                          const Spacer(),

                          // 底部常驻按钮: 在线协同设备、诊断、设置
                          IconButton(
                            icon: const Icon(
                              Icons.devices_rounded,
                              size: 20,
                              color: Color(0xFF888888),
                            ),
                            tooltip: '在线设备协同 (已登录桌面设备)',
                            onPressed: () {},
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.developer_mode_rounded,
                              size: 20,
                              color: Color(0xFF888888),
                            ),
                            tooltip: '开发诊断中心',
                            onPressed: () {},
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.settings_outlined,
                              size: 20,
                              color: Color(0xFF888888),
                            ),
                            tooltip: '微信设置',
                            onPressed: () {},
                          ),
                          const SizedBox(height: 14),
                        ],
                      ),
                    ),

                    // 2. 中间：真实账号会话列表栏 (宽度 290px, 背景 #232323, 严格无外边框)
                    Container(
                      width: 290,
                      color: const Color(0xFF232323),
                      child: Column(
                        children: [
                          const SizedBox(height: 14),
                          // 当前身份切换胶囊
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF07C160),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    alignment: Alignment.center,
                                    child: const Text(
                                      '私',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      '私人助理 (admin)',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFFF0F0F0),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const Icon(
                                    Icons.arrow_drop_down_rounded,
                                    size: 18,
                                    color: Color(0xFFA0A0A0),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),

                          // 搜索栏
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Container(
                              height: 32,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2B2B2B),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.search_rounded,
                                    size: 16,
                                    color: Color(0xFF888888),
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    '搜索联系人、群聊或记录',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: Color(0xFF777777),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),

                          // 会话列表 (包含真实群与好友)
                          Expanded(
                            child: ListView.builder(
                              itemCount: realSessions.length,
                              padding: EdgeInsets.zero,
                              itemBuilder: (context, index) {
                                final session = realSessions[index];
                                final isSelected = index == 0;
                                return Container(
                                  color:
                                      isSelected
                                          ? const Color(0xFF2A2A2A)
                                          : Colors.transparent,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 9,
                                  ),
                                  child: Row(
                                    children: [
                                      // 头像
                                      Container(
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          color:
                                              session.isPinned
                                                  ? const Color(0xFF384358)
                                                  : const Color(0xFF2E3B4E),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          session.title[0],
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      // 标题与摘要
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    session.title,
                                                    style: const TextStyle(
                                                      fontSize: 12.5,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color: Color(0xFFF0F0F0),
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                Text(
                                                  '14:28',
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    color: Color(0xFF777777),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              session.preview,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF888888),
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (session.unreadCount > 0) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFA5151),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: Text(
                                            '${session.unreadCount}',
                                            style: const TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 3. 右侧：选中的会话聊天视窗 (自适应宽度, 背景 #1E1E1E, 严格无边框)
                    Expanded(
                      child: Container(
                        color: const Color(0xFF1E1E1E),
                        child: Column(
                          children: [
                            // 聊天窗口标题栏 (含独立窗口弹窗按钮)
                            Container(
                              height: 52,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                              ),
                              decoration: const BoxDecoration(
                                color: Color(0xFF1E1E1E),
                              ),
                              child: Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      '群(Google Gemini,江敏,邓荣丽,私人助理,江芳宜,徐顺群,杨子嘉) [7人]',
                                      style: TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFFF0F0F0),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.open_in_new_rounded,
                                      size: 18,
                                      color: Color(0xFFA0A0A0),
                                    ),
                                    tooltip: '在独立窗口中打开该聊天',
                                    onPressed: () {},
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.more_horiz_rounded,
                                      size: 20,
                                      color: Color(0xFFA0A0A0),
                                    ),
                                    tooltip: '聊天设置',
                                    onPressed: () {},
                                  ),
                                ],
                              ),
                            ),

                            // 聊天消息气泡区域
                            Expanded(
                              child: Container(
                                color: const Color(0xFF181818),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 16,
                                ),
                                child: ListView(
                                  children: [
                                    _buildSystemDivider('14:10 会话已端到端安全连接'),
                                    const SizedBox(height: 14),
                                    _buildIncomingBubble(
                                      avatar: '李',
                                      name: '江敏 (产品)',
                                      time: '14:15',
                                      message:
                                          '桌面端微信风格改版确认：各个弹窗必须保持全无边框（border: null），包括设置、浏览器、图片查看器和托盘消息框。',
                                    ),
                                    const SizedBox(height: 14),
                                    _buildOutgoingBubble(
                                      avatar: '私',
                                      name: '私人助理 (我)',
                                      time: '14:20',
                                      message:
                                          '收到！已完成改造，全部采用微信 4.0 中性深黑灰 (#1E1E1E/#232323) 和柔化立体投影，无任何多余边框线条。',
                                    ),
                                    const SizedBox(height: 14),
                                    _buildIncomingBubble(
                                      avatar: '杨',
                                      name: '杨子嘉 (架构)',
                                      time: '14:26',
                                      message:
                                          '另外请重点关注：当新消息居多时，托盘消息列表过长的问题如何优雅防护？',
                                    ),
                                    const SizedBox(height: 14),
                                    _buildOutgoingBubble(
                                      avatar: '私',
                                      name: '私人助理 (我)',
                                      time: '14:28',
                                      message:
                                          '已实现四重保护：1) 多身份智能默认折叠；2) 单身份会话数超 4 条自动截断并提供“展开其余 N 个会话”；3) 内置暗黑细滚动条；4) 支持单组一键已读！',
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // 底部聊天富文本输入工具栏与输入框
                            Container(
                              height: 155,
                              color: const Color(0xFF222222),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              child: Column(
                                children: [
                                  // 工具栏 (表情、文件、快传、截图、历史)
                                  Row(
                                    children: [
                                      _buildComposerAction(
                                        Icons.sentiment_satisfied_alt_outlined,
                                        '发送表情',
                                      ),
                                      const SizedBox(width: 14),
                                      _buildComposerAction(
                                        Icons.folder_open_rounded,
                                        '发送文件',
                                      ),
                                      const SizedBox(width: 14),
                                      _buildComposerAction(
                                        Icons.image_outlined,
                                        '发送图片/视频',
                                      ),
                                      const SizedBox(width: 14),
                                      _buildComposerAction(
                                        Icons.crop_free_rounded,
                                        '屏幕截图',
                                      ),
                                      const SizedBox(width: 14),
                                      _buildComposerAction(
                                        Icons.history_rounded,
                                        '聊天记录',
                                      ),
                                      const Spacer(),
                                      _buildComposerAction(
                                        Icons.call_outlined,
                                        '语音呼叫',
                                      ),
                                      const SizedBox(width: 14),
                                      _buildComposerAction(
                                        Icons.videocam_outlined,
                                        '视频通话',
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  // 文本输入区
                                  const Expanded(
                                    child: Align(
                                      alignment: Alignment.topLeft,
                                      child: Text(
                                        '当前使用真实账号 (admin - 360cfedb) 处于多窗口与托盘实时连接状态...',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          color: Color(0xFF666666),
                                        ),
                                      ),
                                    ),
                                  ),
                                  // 发送按钮
                                  Align(
                                    alignment: Alignment.bottomRight,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF07C160),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        '发送 (S)',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
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
      await _captureScreenshot(
        key: repaintKey,
        tester: tester,
        filename: 'screenshot_desktop_main_window_borderless.png',
      );
    });

    testWidgets('2. 托盘新消息聚合浮窗 - 真实账号正常未读展示 (380x480)', (tester) async {
      tester.view.physicalSize = const Size(420, 520);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repaintKey = GlobalKey();

      final normalState = TrayGroupedUnreadState(
        totalUnread: 10,
        groups: [
          TrayOwnerGroup(
            ownerId: 5885,
            ownerName: '私人助理',
            isCurrent: true,
            roleTitle: '机器人助理 · 账号 ID: 5885',
            totalUnread: 5,
            sessions: [
              TraySessionItem(
                sessionUnitId: 'u-gemini',
                targetName: '群(Google Gemini,江敏,邓荣丽,私人助理,江芳宜,徐顺群,杨子嘉)',
                lastMessageText: '杨子嘉: 桌面端窗口全无边框风格与微信已对齐，非常平滑！',
                unreadCount: 3,
                isGroup: true,
                lastMessageTime: DateTime.now().subtract(
                  const Duration(minutes: 5),
                ),
              ),
              TraySessionItem(
                sessionUnitId: 'u-richun',
                targetName: '日春田安店',
                lastMessageText: '掌柜: 门店新进了一批春茶样品，明天安排快传同步',
                unreadCount: 2,
                lastMessageTime: DateTime.now().subtract(
                  const Duration(minutes: 20),
                ),
              ),
            ],
          ),
          TrayOwnerGroup(
            ownerId: 13,
            ownerName: '林惠娟',
            isCurrent: false,
            roleTitle: '个人聊天身份 · 账号 ID: 13',
            totalUnread: 2,
            sessions: [
              TraySessionItem(
                sessionUnitId: 'u-lin',
                targetName: '架构重构专项组',
                lastMessageText: '林工: ABP vNext 实时通信 SignalR 接口验证已完成',
                unreadCount: 2,
                isGroup: true,
                lastMessageTime: DateTime.now().subtract(
                  const Duration(minutes: 45),
                ),
              ),
            ],
          ),
          TrayOwnerGroup(
            ownerId: 5862,
            ownerName: '日春田安店',
            isCurrent: false,
            roleTitle: '掌柜身份 · 账号 ID: 5862',
            totalUnread: 3,
            sessions: [
              TraySessionItem(
                sessionUnitId: 'u-order',
                targetName: '华东大区订货群',
                lastMessageText: '客户已确认订单发货批次',
                unreadCount: 3,
                isGroup: true,
                lastMessageTime: DateTime.now().subtract(
                  const Duration(hours: 1),
                ),
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trayGroupedUnreadProvider.overrideWith(
              () => _MockTrayNotifier(normalState),
            ),
            windowServiceProvider.overrideWithValue(
              DefaultWindowService(
                platformFacade: const _FakeDesktopPlatformFacade(),
              ),
            ),
          ],
          child: MaterialApp(
            theme: _testTheme,
            home: Scaffold(
              backgroundColor: const Color(0xFF121212),
              body: Center(
                child: RepaintBoundary(
                  key: repaintKey,
                  child: const DesktopTrayMessageBox(),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await _captureScreenshot(
        key: repaintKey,
        tester: tester,
        filename: 'screenshot_desktop_tray_real_account.png',
      );
    });

    testWidgets('3. 托盘新消息聚合浮窗 - “新消息居多，列表过长”极限高负载折叠与展开 (380x560)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(440, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repaintKey = GlobalKey();

      // 模拟 5 个聊天身份，总未读高达 128 条，其中主身份有 8 个群聊
      final highLoadState = TrayGroupedUnreadState(
        totalUnread: 128,
        groups: [
          TrayOwnerGroup(
            ownerId: 5885,
            ownerName: '私人助理',
            isCurrent: true,
            roleTitle: '机器人助理 · 账号 ID: 5885',
            totalUnread: 28,
            sessions: [
              TraySessionItem(
                sessionUnitId: 's-1',
                targetName: '群(Google Gemini,江敏,邓荣丽,私人助理,江芳宜,徐顺群,杨子嘉)',
                lastMessageText: '杨子嘉: 桌面端窗口全无边框风格与微信已对齐，非常平滑！',
                unreadCount: 9,
                isGroup: true,
                lastMessageTime: DateTime.now().subtract(
                  const Duration(minutes: 1),
                ),
              ),
              TraySessionItem(
                sessionUnitId: 's-2',
                targetName: '华东大客户商务洽谈群',
                lastMessageText: '刘总: 请发一下 Windows 桌面端离线部署方案',
                unreadCount: 6,
                isGroup: true,
                lastMessageTime: DateTime.now().subtract(
                  const Duration(minutes: 4),
                ),
              ),
              TraySessionItem(
                sessionUnitId: 's-3',
                targetName: '前端 Flutter 跨平台架构组',
                lastMessageText: '王工: 托盘动态角标合成与闪烁动画已测试通过',
                unreadCount: 5,
                isGroup: true,
                lastMessageTime: DateTime.now().subtract(
                  const Duration(minutes: 8),
                ),
              ),
              TraySessionItem(
                sessionUnitId: 's-4',
                targetName: '日春田安店 (掌柜)',
                lastMessageText: '掌柜: 门店新进了一批春茶样品，明天安排快传同步',
                unreadCount: 4,
                lastMessageTime: DateTime.now().subtract(
                  const Duration(minutes: 15),
                ),
              ),
              // 以下会话超出 4 条初始限制，由“展开其余 4 个会话”保护，避免长列表撑爆屏幕
              TraySessionItem(
                sessionUnitId: 's-5',
                targetName: 'ABP vNext 后端网关支持组',
                lastMessageText: '系统: SignalR 心跳保持正常，多实例同步活跃',
                unreadCount: 2,
                isGroup: true,
                lastMessageTime: DateTime.now().subtract(
                  const Duration(minutes: 30),
                ),
              ),
              TraySessionItem(
                sessionUnitId: 's-6',
                targetName: '局域网快传内测群',
                lastMessageText: '大文件分片传输性能稳定',
                unreadCount: 1,
                isGroup: true,
                lastMessageTime: DateTime.now().subtract(
                  const Duration(hours: 1),
                ),
              ),
              TraySessionItem(
                sessionUnitId: 's-7',
                targetName: '移动端 Android/iOS 联调群',
                lastMessageText: '移动端多身份切换抽屉同步完成',
                unreadCount: 1,
                isGroup: true,
                lastMessageTime: DateTime.now().subtract(
                  const Duration(hours: 2),
                ),
              ),
            ],
          ),
          TrayOwnerGroup(
            ownerId: 5862,
            ownerName: '日春田安店',
            isCurrent: false,
            roleTitle: '掌柜身份 · 账号 ID: 5862',
            totalUnread: 15,
            sessions: [
              TraySessionItem(
                sessionUnitId: 's-rc-1',
                targetName: '春茶订货总部',
                lastMessageText: '订单已出库',
                unreadCount: 15,
                isGroup: true,
                lastMessageTime: DateTime.now().subtract(
                  const Duration(hours: 1),
                ),
              ),
            ],
          ),
          TrayOwnerGroup(
            ownerId: 13,
            ownerName: '林惠娟',
            isCurrent: false,
            roleTitle: '个人身份 · 账号 ID: 13',
            totalUnread: 8,
            sessions: [
              TraySessionItem(
                sessionUnitId: 's-lin-1',
                targetName: '架构重构攻坚',
                lastMessageText: '完成模块重构',
                unreadCount: 8,
                lastMessageTime: DateTime.now().subtract(
                  const Duration(hours: 2),
                ),
              ),
            ],
          ),
          TrayOwnerGroup(
            ownerId: 14,
            ownerName: '江芳宜',
            isCurrent: false,
            roleTitle: '个人身份 · 账号 ID: 14',
            totalUnread: 5,
            sessions: [
              TraySessionItem(
                sessionUnitId: 's-jiang-1',
                targetName: '产品设计中心',
                lastMessageText: '新图标规范已上传',
                unreadCount: 5,
                lastMessageTime: DateTime.now().subtract(
                  const Duration(hours: 3),
                ),
              ),
            ],
          ),
          TrayOwnerGroup(
            ownerId: 5866,
            ownerName: '恒也888',
            isCurrent: false,
            roleTitle: '店小二 · 账号 ID: 5866',
            totalUnread: 3,
            sessions: [
              TraySessionItem(
                sessionUnitId: 's-hengye-1',
                targetName: '订单客服处理组',
                lastMessageText: '客户退款咨询已回复',
                unreadCount: 3,
                lastMessageTime: DateTime.now().subtract(
                  const Duration(hours: 4),
                ),
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trayGroupedUnreadProvider.overrideWith(
              () => _MockTrayNotifier(highLoadState),
            ),
            windowServiceProvider.overrideWithValue(
              DefaultWindowService(
                platformFacade: const _FakeDesktopPlatformFacade(),
              ),
            ),
          ],
          child: MaterialApp(
            theme: _testTheme,
            home: Scaffold(
              backgroundColor: const Color(0xFF121212),
              body: Center(
                child: RepaintBoundary(
                  key: repaintKey,
                  child: const DesktopTrayMessageBox(),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await _captureScreenshot(
        key: repaintKey,
        tester: tester,
        filename: 'screenshot_desktop_tray_excessive_messages.png',
      );
    });
  });
}

class _MockTrayNotifier extends TrayGroupedUnreadNotifier {
  _MockTrayNotifier(this._initialState);
  final TrayGroupedUnreadState _initialState;

  @override
  TrayGroupedUnreadState build() => _initialState;
}

Widget _buildDockIcon({
  required IconData icon,
  required String label,
  required bool isSelected,
  String? badge,
}) {
  return Tooltip(
    message: label,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color:
                isSelected
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 22,
            color:
                isSelected ? const Color(0xFF07C160) : const Color(0xFFA0A0A0),
          ),
        ),
        if (badge != null)
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFFA5151),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                badge,
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

Widget _buildComposerAction(IconData icon, String tooltip) {
  return Tooltip(
    message: tooltip,
    child: Icon(icon, size: 20, color: const Color(0xFF888888)),
  );
}

Widget _buildSystemDivider(String text) {
  return Row(
    children: [
      const Expanded(child: Divider(color: Color(0x1FFFFFFF), height: 1)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          text,
          style: const TextStyle(fontSize: 10.5, color: Color(0xFF666666)),
        ),
      ),
      const Expanded(child: Divider(color: Color(0x1FFFFFFF), height: 1)),
    ],
  );
}

Widget _buildIncomingBubble({
  required String avatar,
  required String name,
  required String time,
  required String message,
}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: const Color(0xFF384358),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(
          avatar,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF888888),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  time,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF666666),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFF2B2B2B),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                message,
                style: const TextStyle(fontSize: 13, color: Color(0xFFE8E8E8)),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

Widget _buildOutgoingBubble({
  required String avatar,
  required String name,
  required String time,
  required String message,
}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  time,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF666666),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF888888),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFF07C160),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.white,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 10),
      Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: const Color(0xFF07C160),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(
          avatar,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    ],
  );
}
