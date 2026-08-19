import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as image;
import 'package:zxing2/qrcode.dart';

import 'scan_code_models.dart';

/// Pure-Dart decoder used by upload-only platforms (Web and desktop).
///
/// `zxing2` is portable but currently decodes QR codes only. Mobile gallery
/// decoding remains multi-format through the native scanner adapter.
class DecodeImageRequest {
  const DecodeImageRequest({
    required this.bytes,
    this.formats = const <ScanCodeFormat>[ScanCodeFormat.qrCode],
    this.source = ScanCodeSource.album,
  });

  final Uint8List bytes;
  final List<ScanCodeFormat> formats;
  final ScanCodeSource source;
}

/// Platform-neutral image code API.
///
/// It is intentionally separate from image selection. `chooseFile`/WebView can
/// supply bytes from any source and get the same result model as camera scans.
abstract class ImageCodeService {
  Future<ScanCodeResult?> decodeImage(DecodeImageRequest request);
}

final imageCodeServiceProvider = Provider<ImageCodeService>(
  (ref) => const ZxingImageCodeService(),
);

class ZxingImageCodeService implements ImageCodeService {
  const ZxingImageCodeService();

  @override
  Future<ScanCodeResult?> decodeImage(DecodeImageRequest request) async {
    if (request.formats.isNotEmpty &&
        !request.formats.contains(ScanCodeFormat.qrCode)) {
      throw const ScanCodeFailure('图片识别当前支持二维码，请使用相机扫描条形码。');
    }
    try {
      final decodedImage = image.decodeImage(request.bytes);
      if (decodedImage == null) return null;
      final rgba = decodedImage.getBytes(order: image.ChannelOrder.bgra);
      final source = RGBLuminanceSource(
        decodedImage.width,
        decodedImage.height,
        rgba.buffer.asInt32List(),
      );
      final result = QRCodeReader().decode(
        BinaryBitmap(GlobalHistogramBinarizer(source)),
      );
      if (result.text.trim().isEmpty) return null;
      return ScanCodeResult(
        content: result.text.trim(),
        format: ScanCodeFormat.qrCode,
        source: request.source,
      );
    } on ReaderException {
      return null;
    } on FormatException {
      return null;
    }
  }
}
