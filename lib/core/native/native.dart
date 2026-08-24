import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'device.dart';
import 'sensor.dart';
import 'system.dart';

export 'device.dart';
export 'sensor.dart';
export 'system.dart';

/// Unified Native and Device capabilities facade.
///
/// Features:
/// - System: [onUserCaptureScreen], [onThemeChange], [onResize], [onMemoryWarning], [makePhoneCall]
/// - Device: [vibrate], [getBatteryInfo], [getScreenBrightness], [setScreenBrightness]
/// - Sensor: [onAccelerometerChange], [offAccelerometer], [onGyroscopeChange], [offGyroscope], [onProximityChange], [offProximity]
class Native {
  Native._();

  static final NativeSystem system = NativeSystem();
  static final NativeDevice device = NativeDevice();
  static final NativeSensor sensor = NativeSensor();

  // --- System Capabilities ---

  /// Listens to user screenshot capture events.
  static StreamSubscription<DateTime> onUserCaptureScreen(
    void Function(DateTime timestamp) callback,
  ) {
    return system.onUserCaptureScreen.listen(callback);
  }

  /// Listens to system theme brightness changes (Light / Dark).
  static StreamSubscription<Brightness> onThemeChange(
    void Function(Brightness brightness) callback,
  ) {
    return system.onThemeChange.listen(callback);
  }

  /// Listens to system memory pressure warnings.
  static StreamSubscription<DateTime> onMemoryWarning(
    void Function(DateTime timestamp) callback,
  ) {
    return system.onMemoryWarning.listen(callback);
  }

  /// Listens to window size and orientation changes.
  static StreamSubscription<Size> onResize(
    void Function(Size size) callback,
  ) {
    return system.onResize.listen(callback);
  }

  /// Launches phone dialer with [phoneNumber].
  static Future<bool> makePhoneCall(String phoneNumber) {
    return system.makePhoneCall(phoneNumber);
  }

  // --- Device Capabilities ---

  /// Triggers device vibration / haptic feedback.
  static Future<void> vibrate([
    HapticFeedbackType type = HapticFeedbackType.medium,
    int? durationMs,
  ]) {
    return device.vibrate(type: type, durationMs: durationMs);
  }

  /// Retrieves current battery level and status.
  static Future<BatteryInfo> getBatteryInfo() {
    return device.getBatteryInfo();
  }

  /// Retrieves current screen brightness (0.0 to 1.0).
  static Future<double> getScreenBrightness() {
    return device.getScreenBrightness();
  }

  /// Sets application window screen brightness.
  static Future<bool> setScreenBrightness(double brightness) {
    return device.setScreenBrightness(brightness);
  }

  /// Enables/disables the rear-camera flashlight when supported.
  static Future<bool> setFlashlight(bool enabled) {
    return device.setFlashlight(enabled);
  }

  /// Returns media output volume (0.0-1.0), or -1 when unsupported.
  static Future<double> getSystemVolume() {
    return device.getSystemVolume();
  }

  /// Sets media output volume (0.0-1.0).
  static Future<bool> setSystemVolume(double volume) {
    return device.setSystemVolume(volume);
  }

  /// Sets the desktop app-icon badge; currently supported by macOS Dock.
  static Future<bool> setDesktopBadge(int? count) {
    return system.setDesktopBadge(count);
  }

  // --- Sensor Capabilities ---

  /// Listens to accelerometer sensor data (~5 times/second).
  static StreamSubscription<AccelerometerEvent> onAccelerometerChange(
    void Function(AccelerometerEvent event) callback, {
    int intervalMs = 200,
  }) {
    return sensor.listenAccelerometer(callback, intervalMs: intervalMs);
  }

  /// Cancels active accelerometer subscription.
  static void offAccelerometer() {
    sensor.offAccelerometer();
  }

  /// Listens to gyroscope sensor data.
  static StreamSubscription<GyroscopeEvent> onGyroscopeChange(
    void Function(GyroscopeEvent event) callback, {
    int intervalMs = 200,
  }) {
    return sensor.listenGyroscope(callback, intervalMs: intervalMs);
  }

  /// Cancels active gyroscope subscription.
  static void offGyroscope() {
    sensor.offGyroscope();
  }

  /// Listens to proximity sensor data (near / far).
  static StreamSubscription<ProximityEvent> onProximityChange(
    void Function(ProximityEvent event) callback,
  ) {
    return sensor.listenProximity(callback);
  }

  /// Cancels active proximity subscription.
  static void offProximity() {
    sensor.offProximity();
  }
}

/// Riverpod provider exposing Native facade access.
final nativeSystemProvider = Provider<NativeSystem>((ref) => Native.system);
final nativeDeviceProvider = Provider<NativeDevice>((ref) => Native.device);
final nativeSensorProvider = Provider<NativeSensor>((ref) => Native.sensor);
