import 'dart:async';
import 'dart:io' show Platform, Process;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/platform_facade.dart';
import 'clipboard_service.dart';

/// 跨平台屏幕截图服务契约 (ScreenCaptureService)
abstract class ScreenCaptureService {
  /// 触发屏幕截取
  /// - Windows 10/11: 调起原生现代截图工具 (ms-screenclip: / Win+Shift+S 体验)；
  /// - 截屏完成后，Windows 会自动将图像存入系统剪贴板；
  /// - 本服务监听剪贴板图像变更，返回捕获的图像字节流 (Uint8List)；
  /// - 若用户取消或超时则返回 null。
  Future<Uint8List?> capture();
}

class DesktopScreenCaptureService implements ScreenCaptureService {
  DesktopScreenCaptureService({
    required this.clipboardService,
    required this.platformFacade,
  });

  final ClipboardService clipboardService;
  final PlatformFacade platformFacade;

  @override
  Future<Uint8List?> capture() async {
    if (kIsWeb) {
      debugPrint('[ScreenCaptureService] Web 平台截图暂不支持原生剪贴');
      return null;
    }

    if (Platform.isWindows) {
      return _captureWindows();
    } else if (Platform.isMacOS) {
      return _captureMacOS();
    } else if (Platform.isLinux) {
      return _captureLinux();
    }

    return null;
  }

  Future<Uint8List?> _captureWindows() async {
    // 1. 记录调用前剪贴板中的图像大小（用于去重/判断是否产生新截图）
    final prevImage = await clipboardService.readImage();
    final prevLength = prevImage?.length ?? -1;

    try {
      // 启动 Windows 10/11 原生截图协议 ms-screenclip:
      await Process.run('explorer.exe', ['ms-screenclip:']);
    } catch (e) {
      debugPrint('[ScreenCaptureService] 启动 ms-screenclip: 失败: $e');
      // 备选方案: 尝试运行 SnippingTool.exe
      try {
        await Process.run('cmd.exe', ['/c', 'start', 'SnippingTool.exe']);
      } catch (_) {}
    }

    // 2. 轮询剪贴板，等待用户完成截图 (每 350ms 轮询一次，最多等待 30 秒)
    const pollInterval = Duration(milliseconds: 350);
    const maxPollTime = Duration(seconds: 30);
    final stopwatch = Stopwatch()..start();

    while (stopwatch.elapsed < maxPollTime) {
      await Future<void>.delayed(pollInterval);
      try {
        final currentImage = await clipboardService.readImage();
        if (currentImage != null && currentImage.isNotEmpty) {
          // 如果产生新图像数据
          if (currentImage.length != prevLength || prevLength == -1) {
            debugPrint(
              '[ScreenCaptureService] Windows 截屏成功捕获图像: ${currentImage.length} bytes',
            );
            return currentImage;
          }
        }
      } catch (err) {
        debugPrint('[ScreenCaptureService] 读取剪贴板异常: $err');
      }
    }

    debugPrint('[ScreenCaptureService] Windows 截屏等待超时或已取消');
    return null;
  }

  Future<Uint8List?> _captureMacOS() async {
    try {
      // screencapture -i -c: 交互式选区截图并直接复制到剪贴板
      final result = await Process.run('screencapture', ['-i', '-c']);
      if (result.exitCode == 0) {
        return await clipboardService.readImage();
      }
    } catch (e) {
      debugPrint('[ScreenCaptureService] macOS 截屏异常: $e');
    }
    return null;
  }

  Future<Uint8List?> _captureLinux() async {
    try {
      // 尝试调用 gnome-screenshot 截取选区到剪贴板
      final result = await Process.run('gnome-screenshot', ['-a', '-c']);
      if (result.exitCode == 0) {
        return await clipboardService.readImage();
      }
    } catch (e) {
      debugPrint('[ScreenCaptureService] Linux 截屏异常: $e');
    }
    return null;
  }
}

final screenCaptureServiceProvider = Provider<ScreenCaptureService>((ref) {
  final clipboardService = ref.watch(clipboardServiceProvider);
  final platformFacade = ref.watch(platformFacadeProvider);
  return DesktopScreenCaptureService(
    clipboardService: clipboardService,
    platformFacade: platformFacade,
  );
});
