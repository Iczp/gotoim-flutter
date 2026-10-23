import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Capture a small in-memory preview; never persist private page screenshots.
Future<Uint8List?> captureBrowserThumbnail(
  InAppWebViewController controller,
) async {
  try {
    final bytes = await controller.takeScreenshot(
      screenshotConfiguration: ScreenshotConfiguration(
        compressFormat: CompressFormat.JPEG,
        quality: 60,
      ),
    );
    if (bytes == null || bytes.isEmpty) return null;
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 240);
    final ui.FrameInfo frame;
    try {
      frame = await codec.getNextFrame();
    } finally {
      codec.dispose();
    }
    try {
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } finally {
      frame.image.dispose();
    }
  } catch (_) {
    return null;
  }
}
