import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

import 'scan_code_models.dart';

/// 后台 Isolate 中运行的二维码解码顶层函数，避免卡顿 UI 主线程
String? _decodeQrFromBytesIsolate(Uint8List bytes) {
  try {
    final decodedImage = img.decodeImage(bytes);
    if (decodedImage == null) return null;

    // 针对超高分辨率图片（如 4000x3000），等比缩小到适宜尺寸，识别速度提升 5~10 倍
    img.Image targetImage = decodedImage;
    final maxDim = math.max(decodedImage.width, decodedImage.height);
    if (maxDim > 1600) {
      targetImage = img.copyResize(
        decodedImage,
        width: (decodedImage.width * 1600 / maxDim).round(),
        height: (decodedImage.height * 1600 / maxDim).round(),
        interpolation: img.Interpolation.linear,
      );
    }

    final rgba = targetImage.getBytes(order: img.ChannelOrder.bgra);
    final source = RGBLuminanceSource(
      targetImage.width,
      targetImage.height,
      rgba.buffer.asInt32List(),
    );

    try {
      final result = QRCodeReader().decode(
        BinaryBitmap(GlobalHistogramBinarizer(source)),
      );
      if (result.text.trim().isNotEmpty) {
        return result.text.trim();
      }
    } catch (_) {
      // 若缩小后未识别出且原图被缩小过，使用原图全尺寸做一次兜底
      if (maxDim > 1600) {
        final origRgba = decodedImage.getBytes(order: img.ChannelOrder.bgra);
        final origSource = RGBLuminanceSource(
          decodedImage.width,
          decodedImage.height,
          origRgba.buffer.asInt32List(),
        );
        final origResult = QRCodeReader().decode(
          BinaryBitmap(GlobalHistogramBinarizer(origSource)),
        );
        if (origResult.text.trim().isNotEmpty) {
          return origResult.text.trim();
        }
      }
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// 图片二维码检测器（包含结果内存缓存与后台 Isolate 解码）
class ImageQrDetector {
  ImageQrDetector();

  // 内存 LRU 式缓存，记录每个缓存 Key (图片URL/路径/ID) 的扫描结果
  final Map<String, ScanCodeResult?> _cache = <String, ScanCodeResult?>{};

  /// 检查是否已有缓存
  bool hasCache(String cacheKey) => _cache.containsKey(cacheKey);

  /// 读取已有缓存
  ScanCodeResult? getCached(String cacheKey) => _cache[cacheKey];

  /// 从字节流检测二维码（后台计算）
  Future<ScanCodeResult?> detectFromBytes(
    Uint8List bytes, {
    String? cacheKey,
  }) async {
    if (cacheKey != null && _cache.containsKey(cacheKey)) {
      return _cache[cacheKey];
    }

    String? text;
    if (kIsWeb) {
      text = _decodeQrFromBytesIsolate(bytes);
    } else {
      text = await compute(_decodeQrFromBytesIsolate, bytes);
    }

    final result = text != null && text.isNotEmpty
        ? ScanCodeResult(
            content: text,
            format: ScanCodeFormat.qrCode,
            source: ScanCodeSource.album,
          )
        : null;

    if (cacheKey != null) {
      if (_cache.length > 50) {
        _cache.remove(_cache.keys.first);
      }
      _cache[cacheKey] = result;
    }
    return result;
  }

  /// 从本地文件检测二维码
  Future<ScanCodeResult?> detectFromFile(String filePath) async {
    if (kIsWeb) return null;
    if (_cache.containsKey(filePath)) {
      return _cache[filePath];
    }
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      return await detectFromBytes(bytes, cacheKey: filePath);
    } catch (_) {
      return null;
    }
  }
}

final imageQrDetectorProvider = Provider<ImageQrDetector>(
  (ref) => ImageQrDetector(),
);
