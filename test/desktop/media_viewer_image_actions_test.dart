import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:gotoim_flutter/core/media/media_preview.dart';
import 'package:gotoim_flutter/core/platform/platform_facade.dart';
import 'package:gotoim_flutter/core/services/window_service.dart';
import 'package:gotoim_flutter/features/media/presentation/desktop_media_viewer_window.dart';
import 'package:gotoim_flutter/features/chat/presentation/widgets/clipboard_image_confirm_dialog.dart';

class _Platform implements PlatformFacade {
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

class _Windows extends DefaultWindowService {
  _Windows() : super(platformFacade: _Platform(), isSubWindow: true);
  final qr = <String>[];
  final images = <Uint8List>[];
  @override
  Future<bool> handleImageQrResult(String content) async {
    qr.add(content);
    return true;
  }

  @override
  Future<bool> requestImageSend(
    Uint8List bytes, {
    String? fileName,
    String? caption,
  }) async {
    images.add(bytes);
    return false; // Simulate cancelling the main-window confirmation.
  }
}

Future<Uint8List> _qrImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..drawColor(Colors.white, BlendMode.src);
  canvas.translate(32, 32);
  QrPainter(
    data: 'gotoim://user/42',
    version: QrVersions.auto,
  ).paint(canvas, const Size(256, 256));
  final picture = recorder.endRecording();
  final image = await picture.toImage(320, 320);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('standalone viewer decodes QR and forwards actual image bytes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bytes = (await tester.runAsync(_qrImage))!;
    final windows = _Windows();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [windowServiceProvider.overrideWithValue(windows)],
        child: MaterialApp(
          home: DesktopMediaViewerWindow(
            isSubWindow: true,
            items: [
              MediaPreviewItem(
                id: 'image',
                messageId: 'message',
                type: MediaPreviewType.image,
                source: '',
                heroTag: 'image',
                bytes: bytes,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(find.text('识别图中二维码'));
    await tester.pump();
    // Actual decoder runs in an isolate; this is not a mocked recognition result.
    await tester.runAsync(() async {
      for (var i = 0; i < 100 && windows.qr.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
    expect(windows.qr, ['gotoim://user/42']);
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(find.text('发送给朋友'));
    await tester.pumpAndSettle();
    expect(windows.images, [bytes]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final confirm in [false, true]) {
    testWidgets('edited image waits for explicit confirmation: $confirm', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bytes = (await tester.runAsync(_qrImage))!;
      var sends = 0;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: TextButton(
                    onPressed: () {
                      ClipboardImageConfirmDialog.show(
                        context,
                        imageBytes: bytes,
                        recipientLabel: '测试接收人',
                        onAnnotatedSend: (image, caption) async {
                          sends++;
                        },
                      );
                    },
                    child: const Text('打开确认'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开确认'));
      await tester.pumpAndSettle();
      expect(find.text('发送给：测试接收人'), findsOneWidget);
      await tester.tap(find.text('编辑 / 标注'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('完成并发送 (Enter)'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(sends, 0);
      expect(find.text('发送给：测试接收人'), findsOneWidget);
      await tester.tap(find.text(confirm ? '发送 (Enter)' : '取消 (Esc)'));
      await tester.pumpAndSettle();
      expect(sends, confirm ? 1 : 0);
      expect(tester.takeException(), isNull);
    });
  }
}
