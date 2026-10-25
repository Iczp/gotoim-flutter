import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'desktop_window_capabilities.dart';
import 'windows/windows_window_adapter.dart';

/// 桌面平台底层窗口适配器抽象契约
abstract class DesktopWindowPlatformAdapter {
  const DesktopWindowPlatformAdapter();

  DesktopWindowCapabilities get capabilities;

  Future<void> setupCustomTitleBar();
  Future<void> minimize();
  Future<void> toggleMaximize();
  bool isMaximized();
  Future<void> close();
  Future<void> destroy();
  Future<void> hide();
  Future<void> bringToFront();
  Future<bool?> toggleVisibility();
  Future<void> center({int? width, int? height});
  Future<void> startDragging();
  Future<void> setAlwaysOnTop(bool pinned);
  Future<void> setModal(bool modal);
  Future<void> setToolWindow(bool enable);
  Future<void> prepareFrame();
  Future<Map<String, int>?> getWindowRect();

  // 吸附相关
  Future<bool> dockToParent({
    String slotId = 'chat:right',
    required int x,
    required int y,
    required int width,
    required int height,
  });
  Future<bool> updateDockedBounds({
    required int x,
    required int y,
    required int width,
    required int height,
  });
  Future<bool> undockFromParent({bool showWindow = true});
  Future<bool> isDocked();
  Future<void> setDockSlotVisible(String slotId, bool visible);
  Future<void> setBrowserDockVisible(bool visible, {bool route = false});
  Future<Map<String, dynamic>> browserDockDiagnostics();

  // 资料卡相关
  Future<void> positionFlyout({
    required int x,
    required int y,
    required int width,
    required int height,
    bool noActivate = true,
    Map<String, int>? hoverAnchor,
  });

  // 屏幕截图相关
  Future<Map<String, dynamic>?> captureScreen();
  Future<void> showScreenCapture({int? x, int? y, int? width, int? height});

  // 托盘相关
  Future<void> initializeTray();
  Future<void> updateTray(Map<String, dynamic> arguments);
  Future<void> showTrayMenu();
  Future<void> destroyTray();
  Future<void> showTrayFlyout();
}

/// Windows 原生适配实现 (直接委派至既有经实测验证的 WindowsWindowAdapter)
class WindowsDesktopWindowPlatformAdapter extends DesktopWindowPlatformAdapter {
  const WindowsDesktopWindowPlatformAdapter();

  @override
  DesktopWindowCapabilities get capabilities =>
      DesktopWindowCapabilities.windows();

  @override
  Future<void> setupCustomTitleBar() =>
      WindowsWindowAdapter.setupCustomTitleBar();

  @override
  Future<void> minimize() => WindowsWindowAdapter.minimize();

  @override
  Future<void> toggleMaximize() => WindowsWindowAdapter.toggleMaximize();

  @override
  bool isMaximized() => WindowsWindowAdapter.isMaximized();

  @override
  Future<void> close() => WindowsWindowAdapter.close();

  @override
  Future<void> destroy() => WindowsWindowAdapter.destroy();

  @override
  Future<void> hide() => WindowsWindowAdapter.hide();

  @override
  Future<void> bringToFront() => WindowsWindowAdapter.bringToFront();

  @override
  Future<bool?> toggleVisibility() => WindowsWindowAdapter.toggleVisibility();

  @override
  Future<void> center({int? width, int? height}) =>
      WindowsWindowAdapter.center(width: width, height: height);

  @override
  Future<void> startDragging() => WindowsWindowAdapter.startDragging();

  @override
  Future<void> setAlwaysOnTop(bool pinned) =>
      WindowsWindowAdapter.setAlwaysOnTop(pinned);

  @override
  Future<void> setModal(bool modal) => WindowsWindowAdapter.setModal(modal);

  @override
  Future<void> setToolWindow(bool enable) =>
      WindowsWindowAdapter.setToolWindow(enable);

  @override
  Future<void> prepareFrame() => WindowsWindowAdapter.prepareFrame();

  @override
  Future<Map<String, int>?> getWindowRect() =>
      WindowsWindowAdapter.getWindowRect();

  @override
  Future<bool> dockToParent({
    String slotId = 'chat:right',
    required int x,
    required int y,
    required int width,
    required int height,
  }) => WindowsWindowAdapter.dockToParent(
    slotId: slotId,
    x: x,
    y: y,
    width: width,
    height: height,
  );

  @override
  Future<bool> updateDockedBounds({
    required int x,
    required int y,
    required int width,
    required int height,
  }) => WindowsWindowAdapter.updateDockedBounds(
    x: x,
    y: y,
    width: width,
    height: height,
  );

  @override
  Future<bool> undockFromParent({bool showWindow = true}) =>
      WindowsWindowAdapter.undockFromParent(showWindow: showWindow);

  @override
  Future<bool> isDocked() => WindowsWindowAdapter.isDocked();

  @override
  Future<void> setDockSlotVisible(String slotId, bool visible) =>
      WindowsWindowAdapter.setDockSlotVisible(slotId, visible);

  @override
  Future<void> setBrowserDockVisible(bool visible, {bool route = false}) =>
      WindowsWindowAdapter.setBrowserDockVisible(visible, route: route);

  @override
  Future<Map<String, dynamic>> browserDockDiagnostics() =>
      WindowsWindowAdapter.browserDockDiagnostics();

  @override
  Future<void> positionFlyout({
    required int x,
    required int y,
    required int width,
    required int height,
    bool noActivate = true,
    Map<String, int>? hoverAnchor,
  }) => WindowsWindowAdapter.positionFlyout(
    x: x,
    y: y,
    width: width,
    height: height,
    noActivate: noActivate,
    hoverAnchor: hoverAnchor,
  );

  @override
  Future<Map<String, dynamic>?> captureScreen() =>
      WindowsWindowAdapter.captureScreen();

  @override
  Future<void> showScreenCapture({int? x, int? y, int? width, int? height}) =>
      WindowsWindowAdapter.showScreenCapture(
        x: x,
        y: y,
        width: width,
        height: height,
      );

  @override
  Future<void> initializeTray() => WindowsWindowAdapter.initializeTray();

  @override
  Future<void> updateTray(Map<String, dynamic> arguments) =>
      WindowsWindowAdapter.updateTray(arguments);

  @override
  Future<void> showTrayMenu() => WindowsWindowAdapter.showTrayMenu();

  @override
  Future<void> destroyTray() => WindowsWindowAdapter.destroyTray();

  @override
  Future<void> showTrayFlyout() => WindowsWindowAdapter.showTrayFlyout();
}

/// macOS 桌面窗口原生适配实现 (基于 AppKit 与 gotoim/window 原生通信)
class MacosDesktopWindowPlatformAdapter extends DesktopWindowPlatformAdapter {
  const MacosDesktopWindowPlatformAdapter();

  static const _channel = MethodChannel('gotoim/window');

  static bool _maximized = false;

  Future<T?> _invoke<T>(String method, [Object? arguments]) => _channel
      .invokeMethod<T>(method, arguments)
      .timeout(const Duration(seconds: 5));

  @override
  DesktopWindowCapabilities get capabilities =>
      DesktopWindowCapabilities.macos();

  @override
  Future<void> setupCustomTitleBar() async {
    final result = await _invoke<bool>('configure');
    if (result != null) _maximized = result;
  }

  @override
  Future<void> minimize() async {
    await _invoke<bool>('minimize');
  }

  @override
  Future<void> toggleMaximize() async {
    final result = await _invoke<bool>('toggleMaximize');
    if (result != null) _maximized = result;
  }

  @override
  bool isMaximized() => _maximized;

  @override
  Future<void> close() async {
    await _invoke<bool>('close');
  }

  @override
  Future<void> destroy() async {
    await _invoke<bool>('destroy');
  }

  @override
  Future<void> hide() async {
    await _invoke<bool>('hide');
  }

  @override
  Future<void> bringToFront() async {
    await _invoke<bool>('restore');
  }

  @override
  Future<bool?> toggleVisibility() async {
    return _invoke<bool>('toggleVisibility');
  }

  @override
  Future<void> center({int? width, int? height}) async {
    await _invoke<bool>('center', {
      if (width != null) 'width': width,
      if (height != null) 'height': height,
    });
  }

  @override
  Future<void> startDragging() async {
    await _invoke<bool>('drag');
  }

  @override
  Future<void> setAlwaysOnTop(bool pinned) async {
    await _invoke<bool>('pin', pinned);
  }

  @override
  Future<void> setModal(bool modal) async {
    if (modal) throw UnsupportedError('macOS 尚未实现跨窗口模态协议');
  }

  @override
  Future<void> setToolWindow(bool enable) async {
    await _invoke<bool>('setToolWindow', enable);
  }

  @override
  Future<void> prepareFrame() async {
    throw UnsupportedError('macOS 尚未实现原生绘制确认');
  }

  @override
  Future<Map<String, int>?> getWindowRect() async {
    final res = await _invoke<Map>('getWindowRect');
    if (res == null) return null;
    return res.map(
      (key, value) => MapEntry(key.toString(), (value as num).toInt()),
    );
  }

  @override
  Future<bool> dockToParent({
    String slotId = 'chat:right',
    required int x,
    required int y,
    required int width,
    required int height,
  }) async => false;

  @override
  Future<bool> updateDockedBounds({
    required int x,
    required int y,
    required int width,
    required int height,
  }) async => false;

  @override
  Future<bool> undockFromParent({bool showWindow = true}) async => false;

  @override
  Future<bool> isDocked() async => false;

  @override
  Future<void> setDockSlotVisible(String slotId, bool visible) async {} // No docked windows on this platform.

  @override
  Future<void> setBrowserDockVisible(
    bool visible, {
    bool route = false,
  }) async {} // No docked windows on this platform.

  @override
  Future<Map<String, dynamic>> browserDockDiagnostics() async => {
    'supported': false,
    'platform': 'macOS',
    'reason': capabilities.statusReasons['supportsWindowDocking'],
  };

  @override
  Future<void> positionFlyout({
    required int x,
    required int y,
    required int width,
    required int height,
    bool noActivate = true,
    Map<String, int>? hoverAnchor,
  }) async {
    await _invoke<bool>('positionFlyout', {
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'noActivate': noActivate,
      if (hoverAnchor != null) 'hoverAnchor': hoverAnchor,
    });
  }

  @override
  Future<Map<String, dynamic>?> captureScreen() async {
    try {
      final res = await _channel.invokeMethod<Map>('captureScreen');
      if (res != null) {
        return Map<String, dynamic>.from(res);
      }
    } catch (e) {
      debugPrint('[MacosWindowAdapter] captureScreen error: $e');
    }
    return null;
  }

  @override
  Future<void> showScreenCapture({
    int? x,
    int? y,
    int? width,
    int? height,
  }) async {
    await _invoke<bool>('showScreenCapture', {
      if (x != null) 'x': x,
      if (y != null) 'y': y,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
    });
  }

  @override
  Future<void> initializeTray() async {}

  @override
  Future<void> updateTray(Map<String, dynamic> arguments) async {}

  @override
  Future<void> showTrayMenu() async {}

  @override
  Future<void> destroyTray() async {}

  @override
  Future<void> showTrayFlyout() async {}
}

/// Linux 桌面窗口适配实现
class LinuxDesktopWindowPlatformAdapter extends DesktopWindowPlatformAdapter {
  const LinuxDesktopWindowPlatformAdapter();

  static const _channel = MethodChannel('gotoim/window');
  static bool _maximized = false;

  Future<T?> _invoke<T>(String method, [Object? arguments]) => _channel
      .invokeMethod<T>(method, arguments)
      .timeout(const Duration(seconds: 5));

  @override
  DesktopWindowCapabilities get capabilities =>
      DesktopWindowCapabilities.linux();

  @override
  Future<void> setupCustomTitleBar() async {
    final result = await _invoke<bool>('configure');
    if (result != null) _maximized = result;
  }

  @override
  Future<void> minimize() async {
    await _invoke('minimize');
  }

  @override
  Future<void> toggleMaximize() async {
    final result = await _invoke<bool>('toggleMaximize');
    if (result != null) _maximized = result;
  }

  @override
  bool isMaximized() => _maximized;

  @override
  Future<void> close() async {
    await _invoke('close');
  }

  @override
  Future<void> destroy() async {
    await _invoke('destroy');
  }

  @override
  Future<void> hide() async {
    await _invoke('hide');
  }

  @override
  Future<void> bringToFront() async {
    await _invoke('restore');
  }

  @override
  Future<bool?> toggleVisibility() => _invoke<bool>('toggleVisibility');

  @override
  Future<void> center({int? width, int? height}) async {
    await _invoke('center', {
      if (width != null) 'width': width,
      if (height != null) 'height': height,
    });
  }

  @override
  Future<void> startDragging() async {
    await _invoke('drag');
  }

  @override
  Future<void> setAlwaysOnTop(bool pinned) async {
    await _invoke('pin', pinned);
  }

  @override
  Future<void> setModal(bool modal) async {
    if (modal) throw UnsupportedError('Linux 尚未实现跨窗口模态协议');
  }

  @override
  Future<void> setToolWindow(bool enable) async {
    await _invoke('setToolWindow', enable);
  }

  @override
  Future<void> prepareFrame() async {
    throw UnsupportedError('Linux 尚未实现原生绘制确认');
  }

  @override
  Future<Map<String, int>?> getWindowRect() async => null;

  @override
  Future<bool> dockToParent({
    String slotId = 'chat:right',
    required int x,
    required int y,
    required int width,
    required int height,
  }) async {
    debugPrint('[LinuxWindowAdapter] 原生吸附尚未实现 (待后续分流)');
    return false;
  }

  @override
  Future<bool> updateDockedBounds({
    required int x,
    required int y,
    required int width,
    required int height,
  }) async => false;

  @override
  Future<bool> undockFromParent({bool showWindow = true}) async => false;

  @override
  Future<bool> isDocked() async => false;

  @override
  Future<void> setDockSlotVisible(String slotId, bool visible) async {}

  @override
  Future<void> setBrowserDockVisible(
    bool visible, {
    bool route = false,
  }) async {}

  @override
  Future<Map<String, dynamic>> browserDockDiagnostics() async => {
    'supported': false,
    'platform': 'Linux',
    'reason': '阶段 C 待实现 Linux (X11/Wayland) 吸附',
  };

  @override
  Future<void> positionFlyout({
    required int x,
    required int y,
    required int width,
    required int height,
    bool noActivate = true,
    Map<String, int>? hoverAnchor,
  }) async {
    debugPrint('[LinuxWindowAdapter] positionFlyout: 阶段 C 待实现');
  }

  @override
  Future<Map<String, dynamic>?> captureScreen() async => null;

  @override
  Future<void> showScreenCapture({
    int? x,
    int? y,
    int? width,
    int? height,
  }) async {}

  @override
  Future<void> initializeTray() async {}

  @override
  Future<void> updateTray(Map<String, dynamic> arguments) async {}

  @override
  Future<void> showTrayMenu() async {}

  @override
  Future<void> destroyTray() async {}

  @override
  Future<void> showTrayFlyout() async {}
}

/// 非桌面平台兜底适配实现
class FallbackDesktopWindowPlatformAdapter
    extends DesktopWindowPlatformAdapter {
  const FallbackDesktopWindowPlatformAdapter(this.name);
  final String name;

  @override
  DesktopWindowCapabilities get capabilities =>
      DesktopWindowCapabilities.fallback(name);

  @override
  Future<void> setupCustomTitleBar() async {}
  @override
  Future<void> minimize() async {}
  @override
  Future<void> toggleMaximize() async {}
  @override
  bool isMaximized() => false;
  @override
  Future<void> close() async {}
  @override
  Future<void> destroy() async {}
  @override
  Future<void> hide() async {}
  @override
  Future<void> bringToFront() async {}
  @override
  Future<bool?> toggleVisibility() async => null;
  @override
  Future<void> center({int? width, int? height}) async {}
  @override
  Future<void> startDragging() async {}
  @override
  Future<void> setAlwaysOnTop(bool pinned) async {}
  @override
  Future<void> setModal(bool modal) async {}
  @override
  Future<void> setToolWindow(bool enable) async {}
  @override
  Future<void> prepareFrame() async {}
  @override
  Future<Map<String, int>?> getWindowRect() async => null;
  @override
  Future<bool> dockToParent({
    String slotId = 'chat:right',
    required int x,
    required int y,
    required int width,
    required int height,
  }) async => false;
  @override
  Future<bool> updateDockedBounds({
    required int x,
    required int y,
    required int width,
    required int height,
  }) async => false;
  @override
  Future<bool> undockFromParent({bool showWindow = true}) async => false;
  @override
  Future<bool> isDocked() async => false;
  @override
  Future<void> setDockSlotVisible(String slotId, bool visible) async {}
  @override
  Future<void> setBrowserDockVisible(
    bool visible, {
    bool route = false,
  }) async {}
  @override
  Future<Map<String, dynamic>> browserDockDiagnostics() async => {
    'supported': false,
    'platform': name,
    'reason': '非桌面平台',
  };
  @override
  Future<void> positionFlyout({
    required int x,
    required int y,
    required int width,
    required int height,
    bool noActivate = true,
    Map<String, int>? hoverAnchor,
  }) async {}
  @override
  Future<Map<String, dynamic>?> captureScreen() async => null;
  @override
  Future<void> showScreenCapture({
    int? x,
    int? y,
    int? width,
    int? height,
  }) async {}
  @override
  Future<void> initializeTray() async {}
  @override
  Future<void> updateTray(Map<String, dynamic> arguments) async {}
  @override
  Future<void> showTrayMenu() async {}
  @override
  Future<void> destroyTray() async {}
  @override
  Future<void> showTrayFlyout() async {}
}

/// 跨平台桌面窗口适配器统一门面
class DesktopWindowAdapter {
  DesktopWindowAdapter._();

  static DesktopWindowPlatformAdapter? _overrideAdapter;

  @visibleForTesting
  static void setAdapterForTesting(DesktopWindowPlatformAdapter? adapter) {
    _overrideAdapter = adapter;
  }

  static DesktopWindowPlatformAdapter get current {
    if (_overrideAdapter != null) return _overrideAdapter!;
    if (kIsWeb) return const FallbackDesktopWindowPlatformAdapter('Web');
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
        return const WindowsDesktopWindowPlatformAdapter();
      case TargetPlatform.macOS:
        return const MacosDesktopWindowPlatformAdapter();
      case TargetPlatform.linux:
        return const LinuxDesktopWindowPlatformAdapter();
      default:
        return FallbackDesktopWindowPlatformAdapter(defaultTargetPlatform.name);
    }
  }

  static DesktopWindowCapabilities get capabilities => current.capabilities;

  static bool get isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  static bool get isMacOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
  static bool get isLinux =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;
  static bool get isDesktop => isWindows || isMacOS || isLinux;

  // 回调挂钩统一转发至 WindowsWindowAdapter (保持完全向下兼容)
  static Future<void> Function()? get onCloseRequested =>
      WindowsWindowAdapter.onCloseRequested;
  static set onCloseRequested(Future<void> Function()? callback) =>
      WindowsWindowAdapter.onCloseRequested = callback;

  static void Function(String event)? get onTrayEvent =>
      WindowsWindowAdapter.onTrayEvent;
  static set onTrayEvent(void Function(String event)? callback) =>
      WindowsWindowAdapter.onTrayEvent = callback;

  static void Function(String action)? get onHotkey =>
      WindowsWindowAdapter.onHotkey;
  static set onHotkey(void Function(String action)? callback) =>
      WindowsWindowAdapter.onHotkey = callback;

  // 常用操作门面转发
  static const _channel = MethodChannel('gotoim/window');
  static Future<void> setupCustomTitleBar() async {
    if (!isWindows && isDesktop) {
      _channel.setMethodCallHandler((call) async {
        switch (call.method) {
          case 'closeRequested':
            final handler = onCloseRequested;
            if (handler != null) {
              await handler();
            } else {
              await current.hide();
            }
          case 'hotkey':
            if (call.arguments is String) {
              onHotkey?.call(call.arguments as String);
            }
          case 'trayEvent':
            if (call.arguments is String) {
              onTrayEvent?.call(call.arguments as String);
            }
        }
      });
    }
    await current.setupCustomTitleBar();
  }

  static Future<void> minimize() => current.minimize();
  static Future<void> toggleMaximize() => current.toggleMaximize();
  static bool isMaximized() => current.isMaximized();
  static Future<void> close() => current.close();
  static Future<void> destroy() => current.destroy();
  static Future<void> hide() => current.hide();
  static Future<void> bringToFront() => current.bringToFront();
  static Future<bool?> toggleVisibility() => current.toggleVisibility();
  static Future<void> center({int? width, int? height}) =>
      current.center(width: width, height: height);
  static Future<void> startDragging() => current.startDragging();
  static Future<void> setAlwaysOnTop(bool pinned) =>
      current.setAlwaysOnTop(pinned);
  static Future<void> setModal(bool modal) => current.setModal(modal);
  static Future<void> setToolWindow(bool enable) =>
      current.setToolWindow(enable);
  static Future<void> prepareFrame() => current.prepareFrame();
  static Future<Map<String, int>?> getWindowRect() => current.getWindowRect();

  static Future<bool> dockToParent({
    String slotId = 'chat:right',
    required int x,
    required int y,
    required int width,
    required int height,
  }) => current.dockToParent(
    slotId: slotId,
    x: x,
    y: y,
    width: width,
    height: height,
  );

  static Future<bool> updateDockedBounds({
    required int x,
    required int y,
    required int width,
    required int height,
  }) => current.updateDockedBounds(x: x, y: y, width: width, height: height);

  static Future<bool> undockFromParent({bool showWindow = true}) =>
      current.undockFromParent(showWindow: showWindow);

  static Future<bool> isDocked() => current.isDocked();

  static Future<void> setDockSlotVisible(String slotId, bool visible) =>
      current.setDockSlotVisible(slotId, visible);

  static Future<void> setBrowserDockVisible(
    bool visible, {
    bool route = false,
  }) => current.setBrowserDockVisible(visible, route: route);

  static Future<Map<String, dynamic>> browserDockDiagnostics() =>
      current.browserDockDiagnostics();

  static Future<void> positionFlyout({
    required int x,
    required int y,
    required int width,
    required int height,
    bool noActivate = true,
    Map<String, int>? hoverAnchor,
  }) => current.positionFlyout(
    x: x,
    y: y,
    width: width,
    height: height,
    noActivate: noActivate,
    hoverAnchor: hoverAnchor,
  );

  static Future<Map<String, dynamic>?> captureScreen() =>
      current.captureScreen();

  static Future<void> showScreenCapture({
    int? x,
    int? y,
    int? width,
    int? height,
  }) => current.showScreenCapture(x: x, y: y, width: width, height: height);

  static Future<void> initializeTray() => current.initializeTray();
  static Future<void> updateTray(Map<String, dynamic> arguments) =>
      current.updateTray(arguments);
  static Future<void> showTrayMenu() => current.showTrayMenu();
  static Future<void> destroyTray() => current.destroyTray();
  static Future<void> showTrayFlyout() => current.showTrayFlyout();
}
