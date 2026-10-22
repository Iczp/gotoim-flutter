import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Commands target this engine's view and run on the Windows platform thread.
/// Foreground focus must never select the window controlled by another engine.
class WindowsWindowAdapter {
  WindowsWindowAdapter._();
  static const _channel = MethodChannel('gotoim/window');
  static bool _maximized = false;
  static Future<void> Function()? onCloseRequested;
  static void Function(String event)? onTrayEvent;
  static void Function(String action)? onHotkey;
  static bool get isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  static Future<bool?> _invoke(String method, [Object? arguments]) async {
    if (!isWindows) return null;
    try {
      final result = await _channel.invokeMethod<bool>(method, arguments);
      if (result != null) _maximized = result;
      return result;
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      debugPrint('[WindowsWindowAdapter] $method: ${error.code}');
      return null;
    }
  }

  static Future<void> setupCustomTitleBar() async {
    if (!isWindows) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'closeRequested') await onCloseRequested?.call();
      if (call.method == 'trayEvent' && call.arguments is String) {
        onTrayEvent?.call(call.arguments as String);
      }
      if (call.method == 'hotkey' && call.arguments is String) {
        onHotkey?.call(call.arguments as String);
      }
    });
    await _invoke('configure');
  }

  static Future<void> _trayInvoke(String method, [Object? arguments]) async {
    final result = await _channel.invokeMethod<bool>(method, arguments);
    if (result != null) _maximized = result;
  }

  static Future<void> initializeTray() => _trayInvoke('trayInitialize');
  static Future<void> updateTray(Map<String, dynamic> arguments) =>
      _trayInvoke('trayUpdate', arguments);
  static Future<void> showTrayMenu() => _trayInvoke('trayMenu');
  static Future<void> destroyTray() => _trayInvoke('trayDestroy');

  static Future<void> startDragging() async {
    await _invoke('drag');
  }

  static Future<void> minimize() async {
    await _invoke('minimize');
  }

  static Future<void> toggleMaximize() async {
    _maximized = !_maximized;
    await _invoke('toggleMaximize');
  }

  static bool isMaximized() => _maximized;
  static Future<void> setAlwaysOnTop(bool pinned) async {
    await _invoke('pin', pinned);
  }

  static Future<void> setModal(bool modal) async {
    await _invoke('setModal', modal);
  }

  static Future<void> center({int? width, int? height}) async {
    await _invoke('center', {
      if (width != null) 'width': width,
      if (height != null) 'height': height,
    });
  }

  static Future<void> bringToFront() async {
    await _invoke('restore');
  }

  static Future<bool?> toggleVisibility() async {
    return _invoke('toggleVisibility');
  }

  static Future<void> close() async {
    await _invoke('close');
  }

  static Future<void> destroy() async {
    await _invoke('destroy');
  }

  static Future<void> hide() async {
    await _invoke('hide');
  }

  static Future<void> setToolWindow(bool enable) async {
    await _invoke('setToolWindow', enable);
  }

  static Future<void> showTrayFlyout() async {
    await _invoke('trayFlyout');
  }

  static Future<void> positionFlyout({
    required int x,
    required int y,
    required int width,
    required int height,
    bool noActivate = true,
  }) async {
    await _invoke('positionFlyout', {
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'noActivate': noActivate,
    });
  }

  static Future<Map<String, dynamic>?> captureScreen() async {
    if (!isWindows) return null;
    try {
      final res = await _channel.invokeMethod<Map>('captureScreen');
      if (res != null) {
        return Map<String, dynamic>.from(res);
      }
    } catch (e) {
      debugPrint('[WindowsWindowAdapter] captureScreen error: $e');
    }
    return null;
  }

  static Future<void> showScreenCapture({
    int? x,
    int? y,
    int? width,
    int? height,
  }) async {
    await _invoke('showScreenCapture', {
      if (x != null) 'x': x,
      if (y != null) 'y': y,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
    });
  }

  static Future<Map<String, int>?> getWindowRect() async {
    if (!isWindows) return null;
    try {
      final res = await _channel.invokeMethod<Map>('getWindowRect');
      if (res == null) return null;
      return res.map(
        (key, value) => MapEntry(key.toString(), (value as num).toInt()),
      );
    } catch (_) {
      return null;
    }
  }

  /// 将当前窗口作为 WS_CHILD 嵌入挂载到主窗口的指定客户区矩形中
  static Future<bool> dockToParent({
    required int x,
    required int y,
    required int width,
    required int height,
  }) async {
    if (!isWindows) return false;
    debugPrint(
      '[BrowserDock Adapter] dockToParent: x=$x, y=$y, w=$width, h=$height',
    );
    try {
      final res = await _channel.invokeMethod<bool>('dockToParent', {
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      });
      debugPrint('[BrowserDock Adapter] dockToParent native returned: $res');
      return res ?? false;
    } catch (e) {
      debugPrint('[BrowserDock Adapter] dockToParent failed: $e');
      return false;
    }
  }

  /// 更新已吸附子窗口在主窗口客户区内的相对位置与尺寸
  static Future<bool> updateDockedBounds({
    required int x,
    required int y,
    required int width,
    required int height,
  }) async {
    if (!isWindows) return false;
    try {
      final res = await _channel.invokeMethod<bool>('updateDockedBounds', {
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      });
      return res ?? false;
    } catch (e) {
      debugPrint('[BrowserDock Adapter] updateDockedBounds failed: $e');
      return false;
    }
  }

  /// 从主窗口脱离挂载，恢复为独立的 Windows 系统顶层窗口
  static Future<bool> undockFromParent() async {
    if (!isWindows) return false;
    debugPrint('[BrowserDock Adapter] undockFromParent calling native');
    try {
      final res = await _channel.invokeMethod<bool>('undockFromParent');
      debugPrint(
        '[BrowserDock Adapter] undockFromParent native returned: $res',
      );
      return res ?? false;
    } catch (e) {
      debugPrint('[BrowserDock Adapter] undockFromParent failed: $e');
      return false;
    }
  }

  /// 查询当前窗口是否已被吸附/嵌入到主窗口中
  static Future<bool> isDocked() async {
    if (!isWindows) return false;
    try {
      final res = await _channel.invokeMethod<bool>('isDocked');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }
}
