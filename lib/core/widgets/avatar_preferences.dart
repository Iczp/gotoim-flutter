import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum AvatarShape { circle, square }

class AvatarPreferences extends ChangeNotifier {
  AvatarPreferences({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage() {
    _restore();
  }

  static const _key = 'appearance.avatar-shape';
  final FlutterSecureStorage _storage;
  AvatarShape _shape = AvatarShape.circle;
  AvatarShape get shape => _shape;

  Future<void> _restore() async {
    final value = await _storage.read(key: _key);
    final restored = AvatarShape.values.where((shape) => shape.name == value);
    if (restored.isEmpty || restored.first == _shape) return;
    _shape = restored.first;
    notifyListeners();
  }

  Future<void> setShape(AvatarShape value) async {
    if (_shape == value) return;
    _shape = value;
    notifyListeners();
    await _storage.write(key: _key, value: value.name);
  }
}

final avatarPreferencesProvider = ChangeNotifierProvider<AvatarPreferences>(
  (ref) => AvatarPreferences(),
);
