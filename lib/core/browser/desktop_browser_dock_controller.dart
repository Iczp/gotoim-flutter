import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/window_service.dart';

/// 桌面端浏览器吸附挂载状态枚举
enum BrowserDockingStatus {
  /// 未吸附（独立窗口或未打开）
  unattached,

  /// 正在吸附挂载中（等待主窗口占位布局并执行 Win32 SetParent）
  docking,

  /// 已成功作为子控件嵌入主窗口聊天右侧
  docked,

  /// 正在从主窗口脱离并恢复独立窗口
  undocking,
}

/// 桌面端浏览器吸附挂载状态模型
class DesktopBrowserDockState {
  const DesktopBrowserDockState({
    this.status = BrowserDockingStatus.unattached,
    this.width = 520.0,
    this.currentUrl,
    this.currentTitle,
    this.lastError,
  });

  final BrowserDockingStatus status;
  final double width;
  final String? currentUrl;
  final String? currentTitle;
  final String? lastError;

  bool get isDocked => status == BrowserDockingStatus.docked;
  bool get isTransitioning =>
      status == BrowserDockingStatus.docking ||
      status == BrowserDockingStatus.undocking;
  bool get shouldRenderPlaceholder =>
      status == BrowserDockingStatus.docking ||
      status == BrowserDockingStatus.docked;

  DesktopBrowserDockState copyWith({
    BrowserDockingStatus? status,
    double? width,
    String? currentUrl,
    String? currentTitle,
    String? lastError,
    bool clearError = false,
  }) {
    return DesktopBrowserDockState(
      status: status ?? this.status,
      width: width ?? this.width,
      currentUrl: currentUrl ?? this.currentUrl,
      currentTitle: currentTitle ?? this.currentTitle,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

/// 桌面端浏览器吸附挂载状态管理器 (Notifier)
class DesktopBrowserDockNotifier extends Notifier<DesktopBrowserDockState> {
  @override
  DesktopBrowserDockState build() => const DesktopBrowserDockState();

  static const String browserTargetId = 'tool:browser';

  /// 请求以嵌入模式打开指定网址，或将已存在的独立浏览器吸附到右侧
  Future<void> requestDock({String? url, String? title}) async {
    debugPrint(
      '[BrowserDock Dart] requestDock called: url=$url, title=$title, currentStatus=${state.status}',
    );
    if (state.isTransitioning) return;

    final targetUrl = url ?? state.currentUrl ?? 'https://www.bing.com';
    final targetTitle = title ?? state.currentTitle ?? '网页浏览';

    // 如果当前已经是吸附嵌入状态，直接在已嵌入的浏览器中添加新标签页，不重新触发 docking 遮罩
    if (state.isDocked) {
      state = state.copyWith(
        currentUrl: targetUrl,
        currentTitle: targetTitle,
      );
      try {
        final windowService = ref.read(windowServiceProvider);
        await windowService.openWebBrowser(
          url: targetUrl,
          title: targetTitle,
        );
      } catch (e) {
        debugPrint('[BrowserDock Dart] add tab to docked browser failed: $e');
      }
      return;
    }

    state = state.copyWith(
      status: BrowserDockingStatus.docking,
      currentUrl: targetUrl,
      currentTitle: targetTitle,
      clearError: true,
    );

    // 确保主窗口恢复显示并处于前台
    try {
      final windowService = ref.read(windowServiceProvider);
      await windowService.bringToFront('main');
    } catch (_) {}

    // 确保原生独立浏览器窗口已启动/预热（若尚未打开，以 hidden 模式创建）
    try {
      final windowService = ref.read(windowServiceProvider);
      await windowService.openWebBrowser(
        url: state.currentUrl!,
        title: state.currentTitle,
      );
    } catch (e) {
      debugPrint('[BrowserDock Dart] openWebBrowser failed: $e');
      state = state.copyWith(
        status: BrowserDockingStatus.unattached,
        lastError: e.toString(),
      );
    }
  }

  /// 占位区域完成 PostFrameCallback 物理像素计算后，执行挂载
  Future<bool> commitDock({
    required int viewX,
    required int viewY,
    required int width,
    required int height,
  }) async {
    debugPrint(
      '[BrowserDock Dart] commitDock called: status=${state.status}, physical: (x=$viewX, y=$viewY, w=$width, h=$height)',
    );
    if (state.status != BrowserDockingStatus.docking &&
        state.status != BrowserDockingStatus.docked) {
      return false;
    }

    try {
      final windowService = ref.read(windowServiceProvider);
      if (windowService is DefaultWindowService) {
        final success = await windowService.sendBrowserDockCommand(
          x: viewX,
          y: viewY,
          width: width,
          height: height,
        );

        debugPrint(
          '[BrowserDock Dart] sendBrowserDockCommand result: $success',
        );

        if (success) {
          state = state.copyWith(
            status: BrowserDockingStatus.docked,
            clearError: true,
          );
          return true;
        }
      }
    } catch (e) {
      debugPrint('[BrowserDock Dart] commitDock failed: $e');
    }

    // 挂载失败，原子回滚为未吸附状态
    state = state.copyWith(
      status: BrowserDockingStatus.unattached,
      lastError: 'Win32 原生挂载失败，已回退为独立窗口',
    );
    return false;
  }

  /// 占位区域发生位移/尺寸变化时同步更新子窗口
  Future<void> updateDockedBounds({
    required int viewX,
    required int viewY,
    required int width,
    required int height,
  }) async {
    if (!state.isDocked) return;
    try {
      final windowService = ref.read(windowServiceProvider);
      if (windowService is DefaultWindowService) {
        await windowService.sendBrowserUpdateBoundsCommand(
          x: viewX,
          y: viewY,
          width: width,
          height: height,
        );
      }
    } catch (e) {
      debugPrint('[BrowserDock Dart] updateDockedBounds error: $e');
    }
  }

  /// 请求从聊天右侧脱离挂载，恢复为独立系统窗口 (Pop out)
  Future<void> requestUndock() async {
    debugPrint(
      '[BrowserDock Dart] requestUndock called: status=${state.status}, isTransitioning=${state.isTransitioning}',
    );
    if (state.isTransitioning || !state.isDocked) return;
    state = state.copyWith(status: BrowserDockingStatus.undocking);

    try {
      final windowService = ref.read(windowServiceProvider);
      if (windowService is DefaultWindowService) {
        final res = await windowService.sendBrowserUndockCommand();
        debugPrint(
          '[BrowserDock Dart] sendBrowserUndockCommand result: $res',
        );
      }
    } catch (e) {
      debugPrint('[BrowserDock Dart] requestUndock error: $e');
    }

    state = state.copyWith(
      status: BrowserDockingStatus.unattached,
      clearError: true,
    );
  }

  /// 调整右侧分栏宽度
  void setWidth(double width, {double min = 360.0, double max = 800.0}) {
    state = state.copyWith(width: width.clamp(min, max));
  }

  /// 关闭内嵌浏览器分栏
  Future<void> closeDocked() async {
    debugPrint('[BrowserDock Dart] closeDocked called');
    if (state.isDocked) {
      // 先脱离挂载
      await requestUndock();
    }
    // 关闭/隐藏浏览器窗口
    try {
      final windowService = ref.read(windowServiceProvider);
      await windowService.closeWindow(browserTargetId);
    } catch (_) {}
    state = state.copyWith(status: BrowserDockingStatus.unattached);
  }
}

final desktopBrowserDockProvider =
    NotifierProvider<DesktopBrowserDockNotifier, DesktopBrowserDockState>(
      DesktopBrowserDockNotifier.new,
    );
