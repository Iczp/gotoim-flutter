import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/window_service.dart';
import 'desktop_browser_window.dart';

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
    this.requestSeq = 0,
  });

  final BrowserDockingStatus status;
  final double width;
  final String? currentUrl;
  final String? currentTitle;
  final String? lastError;
  final int requestSeq;

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
    int? requestSeq,
    bool clearError = false,
  }) {
    return DesktopBrowserDockState(
      status: status ?? this.status,
      width: width ?? this.width,
      currentUrl: currentUrl ?? this.currentUrl,
      currentTitle: currentTitle ?? this.currentTitle,
      lastError: clearError ? null : (lastError ?? this.lastError),
      requestSeq: requestSeq ?? this.requestSeq,
    );
  }
}

/// 桌面端浏览器吸附挂载状态管理器 (Notifier)
///
/// 采用主窗口内联 Widget 渲染架构（Inline Flutter Texture WebView2）：
/// - 吸附模式直接在主窗口右侧分栏内嵌渲染 [DesktopBrowserWindow]，彻底杜绝跨进程/跨引擎
///   Win32 SetParent + SetWindowRgn 裁剪洞引发的鼠标事件断言崩溃、点击无响应、最大化浮窗残留及死锁问题；
/// - 弹出独立窗口时通过 [WindowService.openWebBrowser] 唤起独立子窗口。
class DesktopBrowserDockNotifier extends Notifier<DesktopBrowserDockState> {
  @override
  DesktopBrowserDockState build() {
    _registerWindowServiceCallbacks();
    return const DesktopBrowserDockState();
  }

  static const String browserTargetId = 'tool:browser';

  void _registerWindowServiceCallbacks() {
    final windowService = ref.read(windowServiceProvider);
    if (windowService is DefaultWindowService) {
      windowService.onBrowserLoadCompleted = (_) {
        onBrowserLoadCompleted();
      };
      windowService.onBrowserDockRequested = (url, title) async {
        await requestDock(url: url, title: title);
      };
    }
  }

  /// 标准化并校验 URL 格式（委托给浏览器核心组件 DesktopBrowserWindow 统一处理）
  static String? validateAndNormalizeUrl(String? rawUrl) =>
      DesktopBrowserWindow.validateAndNormalizeUrl(rawUrl);

  /// 请求以嵌入模式打开指定网址，或将已存在的独立浏览器吸附到主窗口聊天右侧
  Future<void> requestDock({String? url, String? title}) async {
    debugPrint(
      '[BrowserDock Dart] requestDock called: url=$url, title=$title, currentStatus=${state.status}',
    );

    final rawUrl = url ?? state.currentUrl ?? 'https://www.bing.com';
    final cleanedRaw = rawUrl.trim();
    final targetUrl =
        DesktopBrowserWindow.validateAndNormalizeUrl(cleanedRaw) ??
        (cleanedRaw.isEmpty ? 'https://www.bing.com' : cleanedRaw);
    final targetTitle = title ?? state.currentTitle ?? '网页浏览';

    _registerWindowServiceCallbacks();

    final windowService = ref.read(windowServiceProvider);
    // 若当前存在已打开的独立浏览器子窗口，先将其隐藏关闭，防止独立窗口与内嵌分栏并存
    if (windowService.isWindowOpen(browserTargetId)) {
      try {
        await windowService.closeWindow(browserTargetId);
      } catch (_) {}
    }

    // 确保主窗口恢复显示并处于前台
    try {
      await windowService.bringToFront('main');
    } catch (_) {}

    state = state.copyWith(
      status: BrowserDockingStatus.docked,
      currentUrl: targetUrl,
      currentTitle: targetTitle,
      requestSeq: state.requestSeq + 1,
      clearError: true,
    );
  }

  /// 兼容保留：内联 Widget 渲染模式下由 Flutter 布局树直接接管尺寸
  void updatePendingBounds({
    required int viewX,
    required int viewY,
    required int width,
    required int height,
  }) {}

  /// 页面加载完成回调通知
  void onBrowserLoadCompleted() {
    if (state.status == BrowserDockingStatus.docking) {
      state = state.copyWith(
        status: BrowserDockingStatus.docked,
        clearError: true,
      );
    }
  }

  /// 兼容保留：内联模式下无需 Win32 SetParent
  Future<bool> commitDock({
    required int viewX,
    required int viewY,
    required int width,
    required int height,
  }) async {
    state = state.copyWith(
      status: BrowserDockingStatus.docked,
      clearError: true,
    );
    return true;
  }

  /// 兼容保留：内联模式下由 Flutter Row/SizedBox 自动响应尺寸变化
  Future<void> updateDockedBounds({
    required int viewX,
    required int viewY,
    required int width,
    required int height,
  }) async {}

  /// 请求从聊天右侧脱离挂载，弹出恢复为独立系统窗口 (Pop out)
  Future<void> requestUndock({
    bool showWindow = true,
    String? activeUrl,
    String? activeTitle,
  }) async {
    debugPrint(
      '[BrowserDock Dart] requestUndock called: status=${state.status}, showWindow=$showWindow, activeUrl=$activeUrl',
    );
    if (!state.shouldRenderPlaceholder) return;

    final targetUrl = activeUrl ?? state.currentUrl ?? 'https://www.bing.com';
    final targetTitle = activeTitle ?? state.currentTitle ?? '网页浏览';

    state = state.copyWith(
      status: BrowserDockingStatus.unattached,
      currentUrl: targetUrl,
      currentTitle: targetTitle,
      clearError: true,
    );

    if (showWindow) {
      try {
        final windowService = ref.read(windowServiceProvider);
        await windowService.openWebBrowser(
          url: targetUrl,
          title: targetTitle,
          showImmediately: true,
        );
      } catch (e) {
        debugPrint('[BrowserDock Dart] requestUndock error: $e');
      }
    }
  }

  /// 调整右侧分栏宽度
  void setWidth(double width, {double min = 360.0, double max = 800.0}) {
    state = state.copyWith(width: width.clamp(min, max));
  }

  /// 关闭内嵌浏览器分栏
  Future<void> closeDocked() async {
    debugPrint('[BrowserDock Dart] closeDocked called');
    state = state.copyWith(
      status: BrowserDockingStatus.unattached,
      clearError: true,
    );
  }
}

final desktopBrowserDockProvider =
    NotifierProvider<DesktopBrowserDockNotifier, DesktopBrowserDockState>(
      DesktopBrowserDockNotifier.new,
    );
