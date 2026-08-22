import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// System-level device capabilities.
///
/// Features:
/// - [onThemeChange]: Listens for system Light/Dark theme brightness changes.
/// - [onResize]: Listens for app/window size and orientation changes.
/// - [onMemoryWarning]: Listens for system low-memory pressure warnings.
/// - [onUserCaptureScreen]: Listens for user screenshots on supported platforms.
/// - [makePhoneCall]: Launches phone dialer with specified number.
class NativeSystem with WidgetsBindingObserver {
  NativeSystem({
    MethodChannel? methodChannel,
    EventChannel? screenshotChannel,
  })  : _methodChannel = methodChannel ?? const MethodChannel('com.gotoim.native/methods'),
        _screenshotChannel = screenshotChannel ?? const EventChannel('com.gotoim.native/user_capture_screen') {
    _initObservers();
  }

  final MethodChannel _methodChannel;
  final EventChannel _screenshotChannel;

  final StreamController<Brightness> _themeController = StreamController<Brightness>.broadcast();
  final StreamController<Size> _resizeController = StreamController<Size>.broadcast();
  final StreamController<DateTime> _memoryWarningController = StreamController<DateTime>.broadcast();
  Stream<DateTime>? _screenshotStream;

  void _initObservers() {
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {
      // In non-UI unit tests WidgetsBinding might not be initialized yet
    }
  }

  /// Current system platform brightness.
  Brightness get currentBrightness {
    try {
      return PlatformDispatcher.instance.platformBrightness;
    } catch (_) {
      return Brightness.light;
    }
  }

  /// Current logical window size.
  Size get currentWindowSize {
    try {
      final view = PlatformDispatcher.instance.implicitView;
      if (view != null) {
        final ratio = view.devicePixelRatio;
        return Size(view.physicalSize.width / ratio, view.physicalSize.height / ratio);
      }
    } catch (_) {}
    return Size.zero;
  }

  /// Stream of system theme brightness changes (Light / Dark).
  Stream<Brightness> get onThemeChange => _themeController.stream;

  /// Stream of window / orientation resize changes.
  Stream<Size> get onResize => _resizeController.stream;

  /// Stream of system memory pressure warnings.
  Stream<DateTime> get onMemoryWarning => _memoryWarningController.stream;

  /// Stream of user screenshot capture events with safe error degradation.
  Stream<DateTime> get onUserCaptureScreen {
    if (_screenshotStream != null) return _screenshotStream!;

    late StreamController<DateTime> controller;
    StreamSubscription<dynamic>? sub;

    controller = StreamController<DateTime>.broadcast(
      onListen: () {
        try {
          sub = _screenshotChannel.receiveBroadcastStream().listen(
            (dynamic _) => controller.add(DateTime.now()),
            onError: (dynamic error) {
              // Gracefully handle MissingPluginException before full app rebuild
              debugPrint('[NativeSystem] Screenshot channel inactive: $error');
            },
            cancelOnError: false,
          );
        } catch (e) {
          debugPrint('[NativeSystem] Failed to activate screenshot stream: $e');
        }
      },
      onCancel: () {
        sub?.cancel();
        sub = null;
      },
    );

    _screenshotStream = controller.stream;
    return _screenshotStream!;
  }

  /// Launches the system phone dialer with the given [phoneNumber].
  Future<bool> makePhoneCall(String phoneNumber) async {
    final sanitizedNumber = phoneNumber.trim();
    if (sanitizedNumber.isEmpty) return false;

    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'makePhoneCall',
        <String, dynamic>{'phoneNumber': sanitizedNumber},
      );
      return result ?? false;
    } catch (e) {
      debugPrint('[NativeSystem] makePhoneCall fallback: $e');
      return false;
    }
  }

  @override
  void didChangePlatformBrightness() {
    _themeController.add(currentBrightness);
  }

  @override
  void didChangeMetrics() {
    _resizeController.add(currentWindowSize);
  }

  @override
  void didHaveMemoryPressure() {
    _memoryWarningController.add(DateTime.now());
  }

  /// Disposes controllers and removes binding observer.
  void dispose() {
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
    _themeController.close();
    _resizeController.close();
    _memoryWarningController.close();
  }
}
