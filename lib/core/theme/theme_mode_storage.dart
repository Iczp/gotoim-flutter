import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Storage contract for saving and loading the user's [ThemeMode] preference.
abstract class ThemeModeStorage {
  Future<ThemeMode> readThemeMode();
  Future<void> saveThemeMode(ThemeMode mode);
}

/// Secure storage-backed implementation of [ThemeModeStorage].
class SecureThemeModeStorage implements ThemeModeStorage {
  SecureThemeModeStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _themeModeKey = 'gotoim.theme-mode.v1';
  final FlutterSecureStorage _storage;
  ThemeMode? _cached;

  @override
  Future<ThemeMode> readThemeMode() async {
    if (_cached != null) return _cached!;
    try {
      final value = await _storage.read(key: _themeModeKey);
      if (value != null) {
        final mode = _parseThemeMode(value);
        _cached = mode;
        return mode;
      }
    } catch (_) {}
    return ThemeMode.system;
  }

  @override
  Future<void> saveThemeMode(ThemeMode mode) async {
    _cached = mode;
    try {
      await _storage.write(key: _themeModeKey, value: mode.name);
    } catch (_) {}
  }

  ThemeMode _parseThemeMode(String raw) {
    switch (raw.toLowerCase()) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}
