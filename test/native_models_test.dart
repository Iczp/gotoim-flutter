import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/native/native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Native Models Serialization & Deserialization', () {
    test('BatteryInfo parses from map and serializes to map', () {
      final map = {
        'level': 88,
        'isCharging': true,
        'status': 'charging',
      };

      final info = BatteryInfo.fromMap(map);
      expect(info.level, 88);
      expect(info.isCharging, isTrue);
      expect(info.status, BatteryStatus.charging);

      final serialized = info.toMap();
      expect(serialized['level'], 88);
      expect(serialized['isCharging'], isTrue);
      expect(serialized['status'], 'charging');
    });

    test('BatteryInfo handles missing/corrupt values with safe defaults', () {
      final info = BatteryInfo.fromMap({});
      expect(info.level, 100);
      expect(info.isCharging, isFalse);
      expect(info.status, BatteryStatus.unknown);
    });

    test('AccelerometerEvent parses from map correctly', () {
      final map = {
        'x': 0.12,
        'y': 9.81,
        'z': -0.05,
      };

      final event = AccelerometerEvent.fromMap(map);
      expect(event.x, 0.12);
      expect(event.y, 9.81);
      expect(event.z, -0.05);
      expect(event.timestamp, isNotNull);

      final serialized = event.toMap();
      expect(serialized['x'], 0.12);
      expect(serialized['y'], 9.81);
      expect(serialized['z'], -0.05);
    });

    test('GyroscopeEvent parses from map correctly', () {
      final map = {
        'x': 0.01,
        'y': -0.02,
        'z': 0.05,
      };

      final event = GyroscopeEvent.fromMap(map);
      expect(event.x, 0.01);
      expect(event.y, -0.02);
      expect(event.z, 0.05);
      expect(event.timestamp, isNotNull);

      final serialized = event.toMap();
      expect(serialized['x'], 0.01);
      expect(serialized['y'], -0.02);
      expect(serialized['z'], 0.05);
    });

    test('ProximityEvent parses distance and calculates isNear correctly', () {
      final nearMap = {
        'distance': 1.5,
        'isNear': true,
      };
      final nearEvent = ProximityEvent.fromMap(nearMap);
      expect(nearEvent.distance, 1.5);
      expect(nearEvent.isNear, isTrue);

      final farMap = {
        'distance': 10.0,
      };
      final farEvent = ProximityEvent.fromMap(farMap);
      expect(farEvent.distance, 10.0);
      expect(farEvent.isNear, isFalse);
    });
  });
}
