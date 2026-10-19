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

  static Future<void> bringToFront() async {
    await _invoke('restore');
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

  static Future<void> showTrayFlyout() async {
    await _invoke('trayFlyout');
  }
}
