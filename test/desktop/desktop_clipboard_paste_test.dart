import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gotoim_flutter/features/chat/presentation/widgets/clipboard_files_confirm_dialog.dart';
import 'package:gotoim_flutter/features/chat/presentation/widgets/clipboard_image_confirm_dialog.dart';

late Uint8List _testImageBytes;

Widget _buildTestApp(Widget home, {Key? repaintKey}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Microsoft YaHei',
      scaffoldBackgroundColor: const Color(0xFF1E1E1E),
    ),
    home: Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      body: RepaintBoundary(key: repaintKey, child: home),
    ),
  );
}

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
        final userDir = Directory(
          r'C:\Users\ZP\.gemini\antigravity\brain\f3f5edfb-7920-4a04-b0bc-cda5b23e58ef\screenshots',
        );
        if (!userDir.existsSync()) {
          userDir.createSync(recursive: true);
        }
        final userFile = File('${userDir.path}\\$filename');
        await userFile.writeAsBytes(bytes);

        final projectDir = Directory(
          r'F:\Dev\GotoIM\gotoim-flutter\screenshots',
        );
        if (!projectDir.existsSync()) {
          projectDir.createSync(recursive: true);
        }
        final projectFile = File('${projectDir.path}\\$filename');
        await projectFile.writeAsBytes(bytes);
        debugPrint('[Screenshot] Saved -> ${userFile.path}');
      }
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final bgPaint = Paint()..color = const Color(0xFF2C3E50);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 260, 160),
        const Radius.circular(8),
      ),
      bgPaint,
    );
    final accentPaint = Paint()..color = const Color(0xFF07C160);
    canvas.drawRect(const Rect.fromLTWH(0, 0, 260, 6), accentPaint);

    final picture = recorder.endRecording();
    final img = await picture.toImage(260, 160);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    _testImageBytes = byteData!.buffer.asUint8List();

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

  group('桌面端剪贴板预发送确认弹窗测试 (WeChat-style)', () {
    testWidgets('1. 剪贴板图片弹窗渲染、留言与确认发送链路', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repaintKey = GlobalKey();
      ({bool confirmed, String? caption})? dialogResult;

      await tester.pumpWidget(
        _buildTestApp(
          repaintKey: repaintKey,
          Builder(
            builder: (context) {
              return Center(
                child: ElevatedButton(
                  onPressed: () async {
                    dialogResult = await ClipboardImageConfirmDialog.show(
                      context,
                      imageBytes: _testImageBytes,
                    );
                  },
                  child: const Text('打开图片确认弹窗'),
                ),
              );
            },
          ),
        ),
      );

      // 1. 点击按钮弹出图片确认弹窗
      await tester.tap(find.text('打开图片确认弹窗'));
      await tester.pump(const Duration(milliseconds: 300));

      // 2. 验证弹窗基础元素（标题、提示、发送/取消按钮、留言输入框）
      expect(find.text('发送图片'), findsOneWidget);
      expect(find.textContaining('取消'), findsOneWidget);
      expect(find.text('发送 (Enter)'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      // 3. 验证输入随图留言
      await tester.enterText(find.byType(TextField), '请查阅最新架构截图');
      await tester.pump(const Duration(milliseconds: 100));

      // 截图保存图片弹窗
      await _captureScreenshot(
        key: repaintKey,
        tester: tester,
        filename: 'screenshot_desktop_clipboard_image_confirm.png',
      );

      // 4. 点击发送
      await tester.tap(find.text('发送 (Enter)'));
      await tester.pump(const Duration(milliseconds: 300));

      // 5. 校验返回结果
      expect(dialogResult, isNotNull);
      expect(dialogResult!.confirmed, isTrue);
      expect(dialogResult!.caption, equals('请查阅最新架构截图'));
    });

    testWidgets('2. 剪贴板图片弹窗取消链路', (tester) async {
      ({bool confirmed, String? caption})? dialogResult;

      await tester.pumpWidget(
        _buildTestApp(
          Builder(
            builder: (context) {
              return Center(
                child: ElevatedButton(
                  onPressed: () async {
                    dialogResult = await ClipboardImageConfirmDialog.show(
                      context,
                      imageBytes: _testImageBytes,
                    );
                  },
                  child: const Text('打开图片确认弹窗'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('打开图片确认弹窗'));
      await tester.pump(const Duration(milliseconds: 300));

      // 点击取消
      await tester.tap(find.textContaining('取消'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(dialogResult?.confirmed, isFalse);
    });

    testWidgets('3. 剪贴板多文件弹窗渲染、删除单项、留言与批量发送链路', (tester) async {
      // 创建 3 个临时测试文件
      final tempDir = Directory.systemTemp.createTempSync('gotoim_test_files_');
      final file1 = File('${tempDir.path}/系统架构规范.docx')
        ..writeAsStringSync('GotoIM Architecture Document');
      final file2 = File('${tempDir.path}/财务季度报表.xlsx')
        ..writeAsStringSync('GotoIM Financial Q3');
      final file3 = File('${tempDir.path}/客户端构建包.zip')
        ..writeAsStringSync('GotoIM Client Zip Archive Data');

      final testPaths = [file1.path, file2.path, file3.path];
      ({bool confirmed, List<dynamic> files, String? caption})? dialogResult;

      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repaintKey = GlobalKey();

      await tester.pumpWidget(
        _buildTestApp(
          repaintKey: repaintKey,
          Builder(
            builder: (context) {
              return Center(
                child: ElevatedButton(
                  onPressed: () async {
                    dialogResult = await ClipboardFilesConfirmDialog.show(
                      context,
                      filePaths: testPaths,
                    );
                  },
                  child: const Text('打开文件确认弹窗'),
                ),
              );
            },
          ),
        ),
      );

      // 1. 点击打开多文件预发送弹窗
      await tester.tap(find.text('打开文件确认弹窗'));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump(const Duration(milliseconds: 200));

      // 2. 验证标题及文件总数 (3)
      expect(find.textContaining('发送文件 (3 个)'), findsOneWidget);
      expect(find.text('系统架构规范.docx'), findsOneWidget);
      expect(find.text('财务季度报表.xlsx'), findsOneWidget);
      expect(find.text('客户端构建包.zip'), findsOneWidget);

      // 截图保存 3 个文件的待发送确认列表
      await _captureScreenshot(
        key: repaintKey,
        tester: tester,
        filename: 'screenshot_desktop_clipboard_files_confirm.png',
      );

      // 3. 测试删除单项（移除第二个文件：财务季度报表.xlsx）
      final deleteButtons = find.byTooltip('移除此文件');
      expect(deleteButtons, findsNWidgets(3));

      // 点击第 2 个文件的移除按钮
      await tester.tap(deleteButtons.at(1));
      await tester.pump(const Duration(milliseconds: 200));

      // 4. 验证剩余文件为 2 个，标题动态变为 "发送文件 (2 个)"
      expect(find.textContaining('发送文件 (2 个)'), findsOneWidget);
      expect(find.text('财务季度报表.xlsx'), findsNothing);
      expect(find.text('系统架构规范.docx'), findsOneWidget);
      expect(find.text('客户端构建包.zip'), findsOneWidget);

      // 5. 输入附言
      await tester.enterText(find.byType(TextField), '请查阅附件两份文件');
      await tester.pump(const Duration(milliseconds: 100));

      // 6. 点击确认发送
      await tester.tap(find.text('发送 (2)'));
      await tester.pump(const Duration(milliseconds: 300));

      // 7. 校验返回结果
      expect(dialogResult, isNotNull);
      expect(dialogResult!.confirmed, isTrue);
      expect(dialogResult!.files.length, equals(2));
      expect(dialogResult!.caption, equals('请查阅附件两份文件'));

      // 清理临时文件
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    testWidgets('4. 剪贴板多文件全部移除后弹窗自动关闭或不可发送', (tester) async {
      final tempDir = Directory.systemTemp.createTempSync(
        'gotoim_test_single_',
      );
      final file1 = File('${tempDir.path}/单个文件.txt')
        ..writeAsStringSync('Single Test File');

      await tester.pumpWidget(
        _buildTestApp(
          Builder(
            builder: (context) {
              return Center(
                child: ElevatedButton(
                  onPressed: () async {
                    await ClipboardFilesConfirmDialog.show(
                      context,
                      filePaths: [file1.path],
                    );
                  },
                  child: const Text('打开文件确认弹窗'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('打开文件确认弹窗'));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('单个文件.txt'), findsOneWidget);

      // 移除唯一的文件
      await tester.tap(find.byTooltip('移除此文件'));
      await tester.pump(const Duration(milliseconds: 300));

      // 弹窗应自动关闭
      expect(find.text('单个文件.txt'), findsNothing);

      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    testWidgets('5. 视觉截图生成 - 剪贴板图片预发送微信深色风格确认弹窗', (tester) async {
      tester.view.physicalSize = const Size(600, 520);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repaintKey = GlobalKey();

      await tester.pumpWidget(
        _buildTestApp(
          Center(
            child: RepaintBoundary(
              key: repaintKey,
              child: ClipboardImageConfirmDialog(
                imageBytes: _testImageBytes,
                initialCaption: '请查看架构截图并确认无误 (Alt+A 截图直接粘贴)',
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await _captureScreenshot(
        key: repaintKey,
        tester: tester,
        filename: 'screenshot_desktop_clipboard_image_confirm.png',
      );
    });

    testWidgets('6. 视觉截图生成 - 剪贴板多文件批量预发送微信深色风格确认弹窗', (tester) async {
      tester.view.physicalSize = const Size(620, 560);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final tempDir = Directory.systemTemp.createTempSync(
        'gotoim_visual_files_',
      );
      final file1 = File('${tempDir.path}/GotoIM架构规范_v2.docx')
        ..writeAsStringSync('GotoIM Architecture Document Content Here');
      final file2 = File('${tempDir.path}/2026年Q3财务审计报告.xlsx')
        ..writeAsStringSync('GotoIM Financial Q3 Excel Data');
      final file3 = File('${tempDir.path}/GotoIM_Windows_x64_Setup.zip')
        ..writeAsStringSync('GotoIM Client Zip Archive Package Data');

      final testPaths = [file1.path, file2.path, file3.path];
      final repaintKey = GlobalKey();

      await tester.pumpWidget(
        _buildTestApp(
          Center(
            child: RepaintBoundary(
              key: repaintKey,
              child: ClipboardFilesConfirmDialog(
                filePaths: testPaths,
                initialCaption: '已为您整理 3 份项目核心文档，请确认后发送',
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump(const Duration(milliseconds: 200));

      await _captureScreenshot(
        key: repaintKey,
        tester: tester,
        filename: 'screenshot_desktop_clipboard_files_confirm.png',
      );

      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });
  });
}
