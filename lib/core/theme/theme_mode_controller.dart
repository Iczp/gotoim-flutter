import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme_mode_storage.dart';

/// Provider for the theme storage abstraction.
final themeModeStorageProvider = Provider<ThemeModeStorage>(
  (ref) => SecureThemeModeStorage(),
);

/// Controller managing the application's active [ThemeMode].
class ThemeModeController extends Notifier<ThemeMode> {
  late final ThemeModeStorage _storage;
  bool _manuallySet = false;

  @override
  ThemeMode build() {
    _storage = ref.watch(themeModeStorageProvider);
    _manuallySet = false;
    _restore();
    return ThemeMode.system;
  }

  Future<void> _restore() async {
    final savedMode = await _storage.readThemeMode();
    if (!_manuallySet) {
      state = savedMode;
    }
  }

  /// Change theme mode explicitly and persist the selection.
  Future<void> setThemeMode(ThemeMode mode) async {
    _manuallySet = true;
    if (state == mode) return;
    state = mode;
    await _storage.saveThemeMode(mode);
  }

  /// Toggle between Light and Dark mode. If currently System or Light, switches to Dark.
  Future<void> toggleTheme() async {
    final next = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await setThemeMode(next);
  }
}

/// Provider for [ThemeModeController].
final themeModeControllerProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

/// Direct convenient provider for watching the current [ThemeMode].
final themeModeProvider = Provider<ThemeMode>((ref) {
  return ref.watch(themeModeControllerProvider);
});
