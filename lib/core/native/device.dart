import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Haptic feedback style for device vibration.
enum HapticFeedbackType {
  /// Standard device vibration.
  vibrate,

  /// Light impact (e.g. key tap).
  light,

  /// Medium impact (e.g. button click).
  medium,

  /// Heavy impact (e.g. modal pop or destructive action).
  heavy,

  /// Selection change click.
  selection,
}

/// Device battery charging status.
enum BatteryStatus {
  charging,
  discharging,
  full,
  notCharging,
  unknown,
}

/// Structured battery information.
@immutable
class BatteryInfo {
  const BatteryInfo({
    required this.level,
    required this.isCharging,
    this.status = BatteryStatus.unknown,
  });

  /// Battery percentage (0 - 100).
  final int level;

  /// Whether the device is currently connected to power and charging.
  final bool isCharging;

  /// Detailed charging status.
  final BatteryStatus status;

  factory BatteryInfo.fromMap(Map<dynamic, dynamic> map) {
    final statusStr = map['status'] as String? ?? 'unknown';
    final status = BatteryStatus.values.firstWhere(
      (e) => e.name.toLowerCase() == statusStr.toLowerCase(),
      orElse: () => BatteryStatus.unknown,
    );

    return BatteryInfo(
      level: (map['level'] as num?)?.toInt() ?? 100,
      isCharging: map['isCharging'] as bool? ?? false,
      status: status,
    );
  }

  Map<String, dynamic> toMap() => {
        'level': level,
        'isCharging': isCharging,
        'status': status.name,
      };

  @override
  String toString() =>
      'BatteryInfo(level: $level%, isCharging: $isCharging, status: ${status.name})';
}

/// Device hardware capabilities (vibration, battery, screen brightness).
class NativeDevice {
  NativeDevice({
    MethodChannel? methodChannel,
  }) : _methodChannel = methodChannel ?? const MethodChannel('com.gotoim.native/methods');

  final MethodChannel _methodChannel;

  /// Triggers device vibration or haptic feedback.
  ///
  /// If [durationMs] is specified, it will attempt a custom timed vibration on supported native platforms.
  /// Otherwise, it utilizes Flutter's standard [HapticFeedback] corresponding to [type].
  Future<void> vibrate({
    HapticFeedbackType type = HapticFeedbackType.medium,
    int? durationMs,
  }) async {
    if (durationMs != null && durationMs > 0) {
      try {
        await _methodChannel.invokeMethod<void>(
          'vibrate',
          <String, dynamic>{'duration': durationMs},
        );
        return;
      } catch (_) {
        // Fallback to Flutter HapticFeedback if custom timed vibration fails or is unsupported
      }
    }

    switch (type) {
      case HapticFeedbackType.vibrate:
        await HapticFeedback.vibrate();
      case HapticFeedbackType.light:
        await HapticFeedback.lightImpact();
      case HapticFeedbackType.medium:
        await HapticFeedback.mediumImpact();
      case HapticFeedbackType.heavy:
        await HapticFeedback.heavyImpact();
      case HapticFeedbackType.selection:
        await HapticFeedback.selectionClick();
    }
  }

  /// Retrieves the current device battery information.
  Future<BatteryInfo> getBatteryInfo() async {
    try {
      final result = await _methodChannel.invokeMapMethod<dynamic, dynamic>('getBatteryInfo');
      if (result != null) {
        return BatteryInfo.fromMap(result);
      }
    } catch (e) {
      // Graceful fallback for web/desktop/unregistered state
      debugPrint('[NativeDevice] getBatteryInfo fallback: $e');
    }

    // Default safe fallback for unsupported platforms or test environments
    return const BatteryInfo(
      level: 100,
      isCharging: false,
      status: BatteryStatus.unknown,
    );
  }

  /// Retrieves the current screen/window brightness level (0.0 to 1.0).
  Future<double> getScreenBrightness() async {
    try {
      final result = await _methodChannel.invokeMethod<double>('getScreenBrightness');
      if (result != null) {
        return result.clamp(0.0, 1.0);
      }
    } catch (e) {
      debugPrint('[NativeDevice] getScreenBrightness fallback: $e');
    }
    return 1.0;
  }

  /// Sets the application window screen brightness level.
  ///
  /// [brightness] must be between 0.0 (darkest) and 1.0 (brightest).
  Future<bool> setScreenBrightness(double brightness) async {
    final clampedBrightness = brightness.clamp(0.0, 1.0);
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'setScreenBrightness',
        <String, dynamic>{'brightness': clampedBrightness},
      );
      return result ?? true;
    } catch (e) {
      debugPrint('[NativeDevice] setScreenBrightness fallback: $e');
      return false;
    }
  }
}
