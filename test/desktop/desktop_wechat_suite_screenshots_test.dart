import 'dart:io';
import 'dart:ui' as ui;
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gotoim_flutter/core/config/app_environment.dart';
import 'package:gotoim_flutter/core/native_window/desktop_sub_window_chat_view.dart';
import 'package:gotoim_flutter/core/native_window/native_window_payload.dart';
import 'package:gotoim_flutter/core/platform/platform_facade.dart';
import 'package:gotoim_flutter/core/services/clipboard_service.dart';
import 'package:gotoim_flutter/core/services/window_service.dart';
import 'package:gotoim_flutter/core/theme/app_theme_tokens.dart';
import 'package:gotoim_flutter/features/chat/application/chat_controller.dart';
import 'package:gotoim_flutter/features/chat/data/models/chat_message.dart';
import 'package:gotoim_flutter/features/chat/presentation/widgets/chat_composer.dart';
import 'package:gotoim_flutter/features/chat/presentation/widgets/screenshot_annotation_dialog.dart';

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

class _FakeClipboardService implements ClipboardService {
  String? _text;
  Uint8List? _image;

  @override
  Future<void> copy(String value) async => _text = value;

  @override
  Future<String?> read() async => _text;

  @override
  Future<Uint8List?> readImage() async => _image;

  @override
  Future<void> copyImage(Uint8List bytes) async => _image = bytes;

  @override
  Future<List<String>> readFiles() async => [];

  @override
  Future<void> copyFiles(List<String> filePaths) async {}
}

class _MockChatController extends ChangeNotifier implements ChatController {
  @override
  bool get isOfficialAccount => false;

  @override
  List<Map<String, dynamic>> get officialAccountMenus => const [];

  @override
  bool get isMuted => false;

  @override
  ChatMessage? quoting;

  @override
  void quoteMessage(ChatMessage message) {
    quoting = message;
    notifyListeners();
  }

  @override
  bool get isSending => false;

  @override
  bool get mentionVisible => false;

  List get members => const [];

  @override
  Future<bool> hasVoiceRecordingPermission() async => true;

  @override
  Future<void> send(String text) async {}

  @override
  void cancelQuote() {
    quoting = null;
    notifyListeners();
  }

  void removeQuote() {
    quoting = null;
    notifyListeners();
  }

  @override
  void dismissMention() {}

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
  extensions: [AppThemeTokens.dark()],
);

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

Future<Uint8List> _generateSamplePngBytes() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 720, 420));

  final bgPaint = Paint()
    ..shader = ui.Gradient.linear(
      const Offset(0, 0),
      const Offset(720, 420),
      [const Color(0xFF1E293B), const Color(0xFF0F172A)],
    );
  canvas.drawRect(const Rect.fromLTWH(0, 0, 720, 420), bgPaint);

  final cardPaint = Paint()..color = const Color(0xFF334155);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(40, 40, 640, 340),
      const Radius.circular(8),
    ),
    cardPaint,
  );

  final titlePainter = TextPainter(
    text: const TextSpan(
      text: 'GotoIM 架构核心服务监控面板 - Windows 桌面版\n'
          'SignalR 实时状态: Connected (多设备多实例同步中)\n'
          '当前会话: 产品研发与架构重构攻坚组\n'
          '敏感数据区: API Token = eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...',
      style: TextStyle(color: Colors.white, fontSize: 16, height: 1.8),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: 600);
  titlePainter.paint(canvas, const Offset(60, 60));

  final picture = recorder.endRecording();
  final image = await picture.toImage(720, 420);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
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
          (call) async => null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('gotoim/window'),
          (call) async => true,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('gotoim/ipc_to_main'),
          (call) async {
            if (call.method == 'chat_load_history') {
              return {
                'items': [
                  {
                    'id': '1',
                    'clientMessageId': 'c1',
                    'serverId': 1,
                    'text': '李工：微信同款聊天输入框与截图功能全面落地测试中！',
                    'isMe': false,
                    'time': DateTime.now().subtract(const Duration(minutes: 5)).millisecondsSinceEpoch,
                  },
                  {
                    'id': '2',
                    'clientMessageId': 'c2',
                    'serverId': 2,
                    'text': '架构师：已包含17项专业标注工具，支持Enter与Ctrl+Enter自由切换。',
                    'isMe': true,
                    'time': DateTime.now().subtract(const Duration(minutes: 2)).millisecondsSinceEpoch,
                  },
                ],
              };
            }
            return null;
          },
        );

    dotenv.loadFromString(
      envString: 'APP_NAME=GotoIM\nAPI_BASE_URL=https://api.gotoim.com',
    );

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

  group('微信同款功能专业截图与综合验证', () {
    testWidgets('1. 微信同款桌面端聊天输入框 (ChatComposer Desktop) 渲染截图', (tester) async {
      tester.view.physicalSize = const Size(820, 500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repaintKey = GlobalKey();
      final mockController = _MockChatController();
      final textController = TextEditingController(
        text: '产品研发与架构重构攻坚组：桌面端微信同款聊天输入框已集成完毕！\n'
            '支持自由拖拽调节高度（115px~420px），支持 Enter 与 Ctrl+Enter 快捷键自由切换。',
      );

      final windowService = DefaultWindowService(
        platformFacade: const _FakeDesktopPlatformFacade(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appEnvironmentProvider.overrideWithValue(
              AppEnvironment.fromDotEnv(AppFlavor.development),
            ),
            windowServiceProvider.overrideWithValue(windowService),
            clipboardServiceProvider.overrideWithValue(_FakeClipboardService()),
          ],
          child: MaterialApp(
            theme: _testTheme,
            home: RepaintBoundary(
              key: repaintKey,
              child: Scaffold(
                backgroundColor: const Color(0xFF1E1E1E),
                body: Column(
                  children: [
                    // 模拟上方消息内容展示区
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        color: const Color(0xFF181818),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  color: Color(0xFF07C160),
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  '产品研发与架构重构攻坚组 (当前聊天窗口)',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                                  tooltip: '在独立窗口打开',
                                  onPressed: () {},
                                ),
                              ],
                            ),
                            const Divider(color: Colors.white12, height: 1),
                            const SizedBox(height: 16),
                            // 对话气泡仿真
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2C2C2C),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  '李工：输入框顶部分割线支持自由上下拖拽调整高度，测试完全顺滑！',
                                  style: TextStyle(color: Colors.white, fontSize: 13.5),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF07C160),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  '架构师：截图快捷键 Alt+A 与 17 项标注工具链也已全部就绪。',
                                  style: TextStyle(color: Colors.white, fontSize: 13.5),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // 微信同款桌面端聊天输入框组件
                    ChatComposer(
                      controller: mockController,
                      input: textController,
                      quoteContentBuilder: (q) => const SizedBox.shrink(),
                      isDesktop: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('发送(S)'), findsOneWidget);
      expect(find.textContaining('按 Enter 发送'), findsOneWidget);

      await _captureToDisk(
        key: repaintKey,
        tester: tester,
        filename: 'screenshot_desktop_chat_composer_wechat.png',
      );
    });

    testWidgets('2. 微信同款全功能截图标注工作台 (ScreenshotAnnotationDialog) 渲染截图', (tester) async {
      tester.view.physicalSize = const Size(960, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repaintKey = GlobalKey();
      late Uint8List sampleImageBytes;
      await tester.runAsync(() async {
        sampleImageBytes = await _generateSamplePngBytes();
      });

      final windowService = DefaultWindowService(
        platformFacade: const _FakeDesktopPlatformFacade(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appEnvironmentProvider.overrideWithValue(
              AppEnvironment.fromDotEnv(AppFlavor.development),
            ),
            windowServiceProvider.overrideWithValue(windowService),
            clipboardServiceProvider.overrideWithValue(_FakeClipboardService()),
          ],
          child: MaterialApp(
            theme: _testTheme,
            home: RepaintBoundary(
              key: repaintKey,
              child: Scaffold(
                backgroundColor: Colors.black.withValues(alpha: 0.85),
                body: ScreenshotAnnotationDialog(
                  imageBytes: sampleImageBytes,
                  initialCaption: '攻坚组重点排查：请各位复核标记处的 API Token 与 SignalR 网关并发原子性！',
                ),
              ),
            ),
          ),
        ),
      );

      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 点击矩形标注工具，激活二级调色盘
      final rectFinder = find.byTooltip('矩形框');
      if (rectFinder.evaluate().isNotEmpty) {
        await tester.tap(rectFinder);
        await tester.pump();
      }

      await _captureToDisk(
        key: repaintKey,
        tester: tester,
        filename: 'screenshot_desktop_screenshot_annotation_workbench.png',
      );
    });

    testWidgets('3. 微信同款独立子窗口 (DesktopSubWindowChatView) 渲染截图', (tester) async {
      tester.view.physicalSize = const Size(620, 580);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repaintKey = GlobalKey();
      final windowService = DefaultWindowService(
        platformFacade: const _FakeDesktopPlatformFacade(),
      );

      const payload = NativeWindowPayload(
        type: SubWindowType.chat,
        title: '产品研发与架构重构攻坚组 (独立窗口)',
        targetId: 'su_1001',
        sessionUnitId: 'su_1001',
        ownerId: 1001,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appEnvironmentProvider.overrideWithValue(
              AppEnvironment.fromDotEnv(AppFlavor.development),
            ),
            windowServiceProvider.overrideWithValue(windowService),
            clipboardServiceProvider.overrideWithValue(_FakeClipboardService()),
          ],
          child: MaterialApp(
            theme: _testTheme,
            home: RepaintBoundary(
              key: repaintKey,
              child: DesktopSubWindowChatView(
                payload: payload,
                controller: WindowController.fromWindowId('101'),
                onRegisterHandler: (_) {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('产品研发与架构重构攻坚组 (独立窗口)'), findsOneWidget);
      expect(find.textContaining('发送(S)'), findsOneWidget);

      await _captureToDisk(
        key: repaintKey,
        tester: tester,
        filename: 'screenshot_desktop_sub_window_chat_wechat.png',
      );
    });

    testWidgets('4. 微信同款移动端/平板紧凑输入栏 (ChatComposer Mobile) 渲染截图', (tester) async {
      tester.view.physicalSize = const Size(420, 260);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repaintKey = GlobalKey();
      final mockController = _MockChatController();
      final textController = TextEditingController(text: '移动端微信同款胶囊输入框与动态发送切换');
      final windowService = DefaultWindowService(
        platformFacade: const _FakeDesktopPlatformFacade(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appEnvironmentProvider.overrideWithValue(
              AppEnvironment.fromDotEnv(AppFlavor.development),
            ),
            windowServiceProvider.overrideWithValue(windowService),
            clipboardServiceProvider.overrideWithValue(_FakeClipboardService()),
          ],
          child: MaterialApp(
            theme: _testTheme,
            home: RepaintBoundary(
              key: repaintKey,
              child: Scaffold(
                backgroundColor: const Color(0xFF1E1E1E),
                body: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      alignment: Alignment.center,
                      child: const Text(
                        '微信移动端同款：语音切换、表情、动态发送键切换',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                    ChatComposer(
                      controller: mockController,
                      input: textController,
                      quoteContentBuilder: (q) => const SizedBox.shrink(),
                      isDesktop: false,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('发送'), findsOneWidget);

      await _captureToDisk(
        key: repaintKey,
        tester: tester,
        filename: 'screenshot_mobile_chat_composer_wechat.png',
      );
    });
  });
}
