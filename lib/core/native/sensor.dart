import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 3-axis accelerometer sensor data (m/s²).
@immutable
class AccelerometerEvent {
  const AccelerometerEvent({
    required this.x,
    required this.y,
    required this.z,
    required this.timestamp,
  });

  final double x;
  final double y;
  final double z;
  final DateTime timestamp;

  factory AccelerometerEvent.fromMap(Map<dynamic, dynamic> map) {
    return AccelerometerEvent(
      x: (map['x'] as num?)?.toDouble() ?? 0.0,
      y: (map['y'] as num?)?.toDouble() ?? 0.0,
      z: (map['z'] as num?)?.toDouble() ?? 0.0,
      timestamp: DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'x': x,
        'y': y,
        'z': z,
        'timestamp': timestamp.toIso8601String(),
      };

  @override
  String toString() =>
      'AccelerometerEvent(x: ${x.toStringAsFixed(2)}, y: ${y.toStringAsFixed(2)}, z: ${z.toStringAsFixed(2)})';
}

/// 3-axis gyroscope sensor data (rad/s).
@immutable
class GyroscopeEvent {
  const GyroscopeEvent({
    required this.x,
    required this.y,
    required this.z,
    required this.timestamp,
  });

  final double x;
  final double y;
  final double z;
  final DateTime timestamp;

  factory GyroscopeEvent.fromMap(Map<dynamic, dynamic> map) {
    return GyroscopeEvent(
      x: (map['x'] as num?)?.toDouble() ?? 0.0,
      y: (map['y'] as num?)?.toDouble() ?? 0.0,
      z: (map['z'] as num?)?.toDouble() ?? 0.0,
      timestamp: DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'x': x,
        'y': y,
        'z': z,
        'timestamp': timestamp.toIso8601String(),
      };

  @override
  String toString() =>
      'GyroscopeEvent(x: ${x.toStringAsFixed(2)}, y: ${y.toStringAsFixed(2)}, z: ${z.toStringAsFixed(2)})';
}

/// Proximity sensor data.
@immutable
class ProximityEvent {
  const ProximityEvent({
    required this.distance,
    required this.isNear,
  });

  /// Distance in centimeters (or sensor max range if far).
  final double distance;

  /// Whether an object is near the device screen.
  final bool isNear;

  factory ProximityEvent.fromMap(Map<dynamic, dynamic> map) {
    final distance = (map['distance'] as num?)?.toDouble() ?? 0.0;
    final isNear = map['isNear'] as bool? ?? (distance < 5.0);
    return ProximityEvent(
      distance: distance,
      isNear: isNear,
    );
  }

  Map<String, dynamic> toMap() => {
        'distance': distance,
        'isNear': isNear,
      };

  @override
  String toString() => 'ProximityEvent(isNear: $isNear, distance: ${distance}cm)';
}

/// Hardware motion and environmental sensor management.
class NativeSensor {
  NativeSensor({
    EventChannel? accelerometerChannel,
    EventChannel? gyroscopeChannel,
    EventChannel? proximityChannel,
  })  : _accelerometerChannel = accelerometerChannel ?? const EventChannel('com.gotoim.native/accelerometer'),
        _gyroscopeChannel = gyroscopeChannel ?? const EventChannel('com.gotoim.native/gyroscope'),
        _proximityChannel = proximityChannel ?? const EventChannel('com.gotoim.native/proximity');

  final EventChannel _accelerometerChannel;
  final EventChannel _gyroscopeChannel;
  final EventChannel _proximityChannel;

  Stream<AccelerometerEvent>? _accelerometerStream;
  Stream<GyroscopeEvent>? _gyroscopeStream;
  Stream<ProximityEvent>? _proximityStream;

  StreamSubscription<AccelerometerEvent>? _activeAccelerometerSub;
  StreamSubscription<GyroscopeEvent>? _activeGyroscopeSub;
  StreamSubscription<ProximityEvent>? _activeProximitySub;

  Stream<T> _createSafeStream<T>(
    EventChannel channel,
    T Function(dynamic) converter,
    String tag,
  ) {
    late StreamController<T> controller;
    StreamSubscription<dynamic>? sub;

    controller = StreamController<T>.broadcast(
      onListen: () {
        try {
          sub = channel.receiveBroadcastStream().listen(
            (dynamic event) {
              try {
                controller.add(converter(event));
              } catch (_) {}
            },
            onError: (dynamic error) {
              debugPrint('[$tag] Channel inactive: $error');
            },
            cancelOnError: false,
          );
        } catch (e) {
          debugPrint('[$tag] Failed to listen: $e');
        }
      },
      onCancel: () {
        try {
          sub?.cancel();
        } catch (_) {}
        sub = null;
      },
    );

    return controller.stream;
  }

  /// Stream of accelerometer updates (default rate ~5 times/second = 200ms).
  Stream<AccelerometerEvent> get onAccelerometerChange {
    _accelerometerStream ??= _createSafeStream<AccelerometerEvent>(
      _accelerometerChannel,
      (dynamic event) {
        if (event is Map) {
          return AccelerometerEvent.fromMap(event);
        }
        return AccelerometerEvent(x: 0, y: 0, z: 0, timestamp: DateTime.now());
      },
      'NativeSensor:Accelerometer',
    );
    return _accelerometerStream!;
  }

  /// Subscribes a callback to accelerometer changes.
  StreamSubscription<AccelerometerEvent> listenAccelerometer(
    void Function(AccelerometerEvent event) callback, {
    int intervalMs = 200,
  }) {
    offAccelerometer();
    final sub = onAccelerometerChange.listen(callback);
    _activeAccelerometerSub = sub;
    return sub;
  }

  /// Cancels any active global accelerometer subscription.
  void offAccelerometer() {
    _activeAccelerometerSub?.cancel();
    _activeAccelerometerSub = null;
  }

  /// Stream of gyroscope updates.
  Stream<GyroscopeEvent> get onGyroscopeChange {
    _gyroscopeStream ??= _createSafeStream<GyroscopeEvent>(
      _gyroscopeChannel,
      (dynamic event) {
        if (event is Map) {
          return GyroscopeEvent.fromMap(event);
        }
        return GyroscopeEvent(x: 0, y: 0, z: 0, timestamp: DateTime.now());
      },
      'NativeSensor:Gyroscope',
    );
    return _gyroscopeStream!;
  }

  /// Subscribes a callback to gyroscope changes.
  StreamSubscription<GyroscopeEvent> listenGyroscope(
    void Function(GyroscopeEvent event) callback, {
    int intervalMs = 200,
  }) {
    offGyroscope();
    final sub = onGyroscopeChange.listen(callback);
    _activeGyroscopeSub = sub;
    return sub;
  }

  /// Cancels any active global gyroscope subscription.
  void offGyroscope() {
    _activeGyroscopeSub?.cancel();
    _activeGyroscopeSub = null;
  }

  /// Stream of proximity sensor events.
  Stream<ProximityEvent> get onProximityChange {
    _proximityStream ??= _createSafeStream<ProximityEvent>(
      _proximityChannel,
      (dynamic event) {
        if (event is Map) {
          return ProximityEvent.fromMap(event);
        }
        return const ProximityEvent(distance: 5.0, isNear: false);
      },
      'NativeSensor:Proximity',
    );
    return _proximityStream!;
  }

  /// Subscribes a callback to proximity sensor changes.
  StreamSubscription<ProximityEvent> listenProximity(
    void Function(ProximityEvent event) callback,
  ) {
    offProximity();
    final sub = onProximityChange.listen(callback);
    _activeProximitySub = sub;
    return sub;
  }

  /// Cancels any active global proximity subscription.
  void offProximity() {
    _activeProximitySub?.cancel();
    _activeProximitySub = null;
  }

  /// Cancels all active sensor subscriptions.
  void dispose() {
    offAccelerometer();
    offGyroscope();
    offProximity();
  }
}
