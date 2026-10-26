import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/features/chat/presentation/widgets/desktop_screen_capture_view.dart';
import 'package:gotoim_flutter/core/services/clipboard_service.dart';

class _CaptureClipboard extends SystemClipboardService {
  Uint8List? image;
  @override
  Future<void> copyImage(Uint8List bytes) async {
    image = bytes;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final ratio in [1.0, 1.5, 2.0]) {
    testWidgets('crop follows pointer and logical bounds at DPI $ratio', (
      tester,
    ) async {
      tester.view.devicePixelRatio = ratio;
      tester.view.physicalSize = Size(800 * ratio, 600 * ratio);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('gotoim/window'),
        (_) async => true,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('mixin.one/desktop_multi_window/channels'),
        (_) async => null,
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          const MethodChannel('gotoim/window'),
          null,
        ),
      );

      late Future<dynamic> Function(MethodCall) handler;
      final clipboard = _CaptureClipboard();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [clipboardServiceProvider.overrideWithValue(clipboard)],
          child: MaterialApp(
            home: Scaffold(
              body: DesktopScreenCaptureView(
                onRegisterMethodHandler: (value) => handler = value,
              ),
            ),
          ),
        ),
      );
      final directory = Directory.systemTemp.createTempSync(
        'gotoim-capture-test-',
      );
      final file = File('${directory.path}/screen.png');
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawColor(Colors.blue, BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(
          (800 * ratio).round(),
          (600 * ratio).round(),
        );
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
        picture.dispose();
        await handler(
          MethodCall('show_screen_capture', {
            'imagePath': file.path,
            'width': (800 * ratio).round(),
            'height': (600 * ratio).round(),
            'dpi': (96 * ratio).round(),
            'x': (-400 * ratio).round(),
            'y': (-100 * ratio).round(),
            // Global physical coordinates, frontmost region first.
            'windows': [
              {
                'x': (-300 * ratio).round(),
                'y': 0,
                'width': (200 * ratio).round(),
                'height': (150 * ratio).round(),
              },
              {
                'x': (-350 * ratio).round(),
                'y': (-50 * ratio).round(),
                'width': (450 * ratio).round(),
                'height': (350 * ratio).round(),
              },
            ],
          }),
        );
      });
      addTearDown(() {
        file.deleteSync();
        directory.deleteSync();
      });
      await tester.pump();
      final surface = find.byKey(const ValueKey('screen-capture-canvas'));
      Rect? crop() {
        final dynamic painter =
            tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: surface,
                    matching: find.byType(CustomPaint),
                  ),
                )
                .painter;
        return painter.cropRect as Rect?;
      }

      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: const Offset(10, 10));
      await pointer.moveTo(const Offset(200, 175));
      await tester.pump();
      expect(crop(), const Rect.fromLTRB(100, 100, 300, 250));
      await pointer.moveTo(const Offset(400, 300));
      await tester.pump();
      expect(crop(), const Rect.fromLTWH(50, 50, 450, 350));
      await pointer.down(const Offset(200, 175));
      await pointer.up();
      await tester.pump();
      expect(crop(), const Rect.fromLTRB(100, 100, 300, 250));
      // Dragging outside the selected window always starts a free selection.
      await pointer.down(const Offset(550, 420));
      await pointer.moveTo(const Offset(650, 500));
      await pointer.up();
      await tester.pump();
      expect(crop(), const Rect.fromLTWH(550, 420, 100, 80));
      await pointer.down(const Offset(700, 100));
      await pointer.up();
      await tester.pump();
      expect(crop(), isNull);
      await pointer.down(const Offset(100, 100));
      // No gesture slop or double-click delay: even the first 2px count.
      await pointer.moveTo(const Offset(102, 102));
      await tester.pump();
      expect(crop(), const Rect.fromLTRB(100, 100, 102, 102));
      await pointer.moveTo(const Offset(300, 250));
      await pointer.up();
      await tester.pump();
      expect(crop(), const Rect.fromLTRB(100, 100, 300, 250));

      await pointer.down(const Offset(200, 175));
      await pointer.moveTo(const Offset(1000, 900));
      await pointer.up();
      await tester.pump();
      expect(crop(), const Rect.fromLTWH(600, 450, 200, 150));

      await pointer.down(const Offset(600, 450));
      await pointer.moveTo(const Offset(500, 350));
      await pointer.up();
      await tester.pump();
      expect(crop(), const Rect.fromLTRB(500, 350, 800, 600));
      // Toolbar clicks must never bubble into crop selection/movement.
      await tester.tap(find.byTooltip('矩形框'));
      await tester.pump();
      expect(crop(), const Rect.fromLTRB(500, 350, 800, 600));
      final exported = await tester.runAsync(() async {
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        final watch = Stopwatch()..start();
        while (clipboard.image == null && watch.elapsedMilliseconds < 5000) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        final codec = await ui.instantiateImageCodec(clipboard.image!);
        final frame = await codec.getNextFrame();
        codec.dispose();
        return frame.image;
      });
      expect(exported!.width, (300 * ratio).round());
      expect(exported.height, (250 * ratio).round());
      exported.dispose();
      // Reusing the hidden workbench must discard an interrupted drag.
      await pointer.down(const Offset(550, 400));
      late Future<dynamic> reactivation;
      await tester.runAsync(() async {
        reactivation = handler(
          MethodCall('show_screen_capture', {
            'imagePath': file.path,
            'width': (800 * ratio).round(),
            'height': (600 * ratio).round(),
          }),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      await tester.runAsync(
        () => reactivation.timeout(const Duration(seconds: 5)),
      );
      final nextPointer = await tester.createGesture(
        pointer: 2,
        kind: PointerDeviceKind.mouse,
      );
      await nextPointer.down(const Offset(40, 40));
      await nextPointer.moveTo(const Offset(120, 120));
      await nextPointer.up();
      await pointer.up();
      await tester.pump();
      expect(crop(), const Rect.fromLTRB(40, 40, 120, 120));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
