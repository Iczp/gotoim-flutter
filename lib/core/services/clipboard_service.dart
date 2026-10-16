import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pasteboard/pasteboard.dart';

/// 统一剪贴板能力抽象 (ClipboardService)
///
/// 支持文本、图像 (二进制 PNG/BMP 字节流) 及操作系统文件列表 (如在文件管理器中复制的多个文件)
abstract class ClipboardService {
  /// 写入文本至剪贴板
  Future<void> copy(String value);

  /// 读取剪贴板中的纯文本
  Future<String?> read();

  /// 读取剪贴板中的图像数据 (PNG/BMP 字节流，若无图像则返回 null)
  Future<Uint8List?> readImage();

  /// 写入图像至系统剪贴板
  Future<void> copyImage(Uint8List bytes);

  /// 读取剪贴板中的文件列表路径 (如 Windows 资源管理器复制的多个文件)
  Future<List<String>> readFiles();

  /// 写入文件列表至系统剪贴板
  Future<void> copyFiles(List<String> filePaths);
}

class SystemClipboardService implements ClipboardService {
  @override
  Future<void> copy(String value) =>
      Clipboard.setData(ClipboardData(text: value));

  @override
  Future<String?> read() async => (await Clipboard.getData('text/plain'))?.text;

  @override
  Future<Uint8List?> readImage() async {
    try {
      return await Pasteboard.image;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> copyImage(Uint8List bytes) async {
    try {
      await Pasteboard.writeImage(bytes);
    } catch (_) {}
  }

  @override
  Future<List<String>> readFiles() async {
    try {
      final files = await Pasteboard.files();
      return files;
    } catch (_) {
      return const <String>[];
    }
  }

  @override
  Future<void> copyFiles(List<String> filePaths) async {
    try {
      await Pasteboard.writeFiles(filePaths);
    } catch (_) {}
  }
}

final clipboardServiceProvider = Provider<ClipboardService>(
  (ref) => SystemClipboardService(),
);
