import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/window_service.dart';
import '../widgets/app_toast.dart';

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
  DesktopBrowserDockState build() {
    _registerWindowServiceCallbacks();
    return const DesktopBrowserDockState();
  }

  static const String browserTargetId = 'tool:browser';

  bool _isPageLoaded = false;
  ({int viewX, int viewY, int width, int height})? _pendingBounds;
  ({int viewX, int viewY, int width, int height})? _lastDockedBounds;
  Timer? _loadTimeoutTimer;

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

  /// 标准化并校验 URL 格式（支持补全 https:// 协议、去除多余空白字符、拦截非法 scheme）
  static String? validateAndNormalizeUrl(String? rawUrl) {
    if (rawUrl == null) return null;
    var url = rawUrl.trim();
    if (url.isEmpty) return null;

    if (url.startsWith('//')) {
      url = 'https:$url';
    } else if (!url.startsWith(RegExp(r'^[a-zA-Z][a-zA-Z0-9+\-.]*://'))) {
      final domainRegex = RegExp(r'^([a-zA-Z0-9\-]+\.)+[a-zA-Z]{2,}(/.*)?$');
      final ipRegex =
          RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(:\d+)?(/.*)?$');
      final localhostRegex = RegExp(r'^localhost(:\d+)?(/.*)?$');
      if (domainRegex.hasMatch(url) ||
          ipRegex.hasMatch(url) ||
          localhostRegex.hasMatch(url)) {
        url = 'https://$url';
      } else {
        return null;
      }
    }

    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (uri.host.isEmpty) return null;
    return uri.toString();
  }

  /// 请求以嵌入模式打开指定网址，或将已存在的独立浏览器吸附到右侧
  Future<void> requestDock({String? url, String? title}) async {
    debugPrint(
      '[BrowserDock Dart] requestDock called: url=$url, title=$title, currentStatus=${state.status}',
    );
    if (state.isTransitioning) return;

    final rawUrl = url ?? state.currentUrl ?? 'https://www.bing.com';
    final targetUrl = validateAndNormalizeUrl(rawUrl);
    if (targetUrl == null) {
      debugPrint('[BrowserDock Dart] Invalid URL: $rawUrl');
      showToast('无法打开该链接：网址格式不正确', type: ToastType.error);
      return;
    }
    final targetTitle = title ?? state.currentTitle ?? '网页浏览';

    // 如果当前已经是吸附嵌入状态，直接在已嵌入的浏览器中添加新标签页，不重新触发 docking 遮罩
    if (state.isDocked) {
      state = state.copyWith(currentUrl: targetUrl, currentTitle: targetTitle);
      try {
        final windowService = ref.read(windowServiceProvider);
        await windowService.openWebBrowser(url: targetUrl, title: targetTitle);
      } catch (e) {
        debugPrint('[BrowserDock Dart] add tab to docked browser failed: $e');
      }
      return;
    }

    _isPageLoaded = false;
    // 如果之前已有测量缓存，优先预热待挂载物理边界，确保秒开时无需等待首帧 PostFrameCallback
    _pendingBounds = _lastDockedBounds;
    _loadTimeoutTimer?.cancel();

    state = state.copyWith(
      status: BrowserDockingStatus.docking,
      currentUrl: targetUrl,
      currentTitle: targetTitle,
      clearError: true,
    );

    _registerWindowServiceCallbacks();

    // 确保主窗口恢复显示并处于前台
    try {
      final windowService = ref.read(windowServiceProvider);
      await windowService.bringToFront('main');
    } catch (_) {}

    // 设置安全超时：若网页加载超过 3.5 秒仍未通知完成，强制触发吸附挂载
    _loadTimeoutTimer = Timer(const Duration(milliseconds: 3500), () {
      if (state.status == BrowserDockingStatus.docking && !_isPageLoaded) {
        debugPrint(
          '[BrowserDock Dart] Page load timeout (3.5s), triggering dock commit',
        );
        onBrowserLoadCompleted();
      }
    });

    // 浏览器在后台静默打开（尺寸默认就是点位大小，showImmediately: false）
    try {
      final windowService = ref.read(windowServiceProvider);
      await windowService.openWebBrowser(
        url: state.currentUrl!,
        title: state.currentTitle,
        showImmediately: false,
        initialWidth: state.width.round(),
      );
    } catch (e) {
      debugPrint('[BrowserDock Dart] openWebBrowser failed: $e');
      _loadTimeoutTimer?.cancel();
      _loadTimeoutTimer = null;
      state = state.copyWith(
        status: BrowserDockingStatus.unattached,
        lastError: e.toString(),
      );
    }
  }

  /// 占位区域完成 PostFrameCallback 物理像素计算后，记录待吸附边界
  void updatePendingBounds({
    required int viewX,
    required int viewY,
    required int width,
    required int height,
  }) {
    _pendingBounds = (
      viewX: viewX,
      viewY: viewY,
      width: width,
      height: height,
    );
    _lastDockedBounds = _pendingBounds;
    debugPrint(
      '[BrowserDock Dart] updatePendingBounds: ($_pendingBounds), isPageLoaded=$_isPageLoaded, status=${state.status}',
    );

    // 如果网页已在后台完全加载完毕，立即执行 Win32 挂载
    if (_isPageLoaded && state.status == BrowserDockingStatus.docking) {
      _executeDockCommit();
    }
  }

  /// 后台浏览器页面加载完成回调通知
  void onBrowserLoadCompleted() {
    debugPrint(
      '[BrowserDock Dart] onBrowserLoadCompleted: status=${state.status}, pendingBounds=$_pendingBounds, lastBounds=$_lastDockedBounds',
    );
    _loadTimeoutTimer?.cancel();
    _loadTimeoutTimer = null;
    _isPageLoaded = true;

    if (_pendingBounds == null && _lastDockedBounds != null) {
      _pendingBounds = _lastDockedBounds;
    }

    // 如果占位区域物理尺寸已完成测量，立即执行 Win32 挂载
    if (state.status == BrowserDockingStatus.docking && _pendingBounds != null) {
      _executeDockCommit();
    }
  }

  Future<bool> _executeDockCommit() async {
    if (_pendingBounds == null) return false;
    if (state.status != BrowserDockingStatus.docking) return false;
    final b = _pendingBounds!;
    return commitDock(
      viewX: b.viewX,
      viewY: b.viewY,
      width: b.width,
      height: b.height,
    );
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
          _lastDockedBounds = (
            viewX: viewX,
            viewY: viewY,
            width: width,
            height: height,
          );
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
    _lastDockedBounds = (
      viewX: viewX,
      viewY: viewY,
      width: width,
      height: height,
    );
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
  Future<void> requestUndock({bool showWindow = true}) async {
    debugPrint(
      '[BrowserDock Dart] requestUndock called: status=${state.status}, isTransitioning=${state.isTransitioning}, showWindow=$showWindow',
    );
    if (state.isTransitioning || !state.isDocked) return;
    _loadTimeoutTimer?.cancel();
    _loadTimeoutTimer = null;
    _isPageLoaded = false;
    _pendingBounds = null;
    state = state.copyWith(status: BrowserDockingStatus.undocking);

    try {
      final windowService = ref.read(windowServiceProvider);
      if (windowService is DefaultWindowService) {
        final res = await windowService.sendBrowserUndockCommand(
          showWindow: showWindow,
        );
        debugPrint('[BrowserDock Dart] sendBrowserUndockCommand result: $res');
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
    _loadTimeoutTimer?.cancel();
    _loadTimeoutTimer = null;
    _isPageLoaded = false;
    _pendingBounds = null;
    if (state.isDocked) {
      // 1. 在完全不可见状态下脱离挂载，彻底避免闪现独立窗口
      await requestUndock(showWindow: false);
    }
    // 2. 关闭/隐藏浏览器窗口控制器
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
