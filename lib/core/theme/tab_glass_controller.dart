import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class TabGlassStorage {
  Future<bool> read();
  Future<void> save(bool enabled);
}

class SecureTabGlassStorage implements TabGlassStorage {
  SecureTabGlassStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'gotoim.tab-glass.v1';
  final FlutterSecureStorage _storage;
  bool? _cached;

  @override
  Future<bool> read() async {
    if (_cached != null) return _cached!;
    try {
      final raw = await _storage.read(key: _key);
      _cached = raw == null ? true : raw == 'true';
      return _cached!;
    } catch (_) {
      return true;
    }
  }

  @override
  Future<void> save(bool enabled) async {
    _cached = enabled;
    try {
      await _storage.write(key: _key, value: enabled ? 'true' : 'false');
    } catch (_) {}
  }
}

final tabGlassStorageProvider = Provider<TabGlassStorage>(
  (ref) => SecureTabGlassStorage(),
);

class TabGlassController extends Notifier<bool> {
  late final TabGlassStorage _storage;
  bool _initialized = false;

  @override
  bool build() {
    _storage = ref.watch(tabGlassStorageProvider);
    _initialized = false;
    _load();
    return true;
  }

  Future<void> _load() async {
    final enabled = await _storage.read();
    if (!_initialized) {
      _initialized = true;
      state = enabled;
    }
  }

  Future<void> setEnabled(bool enabled) async {
    _initialized = true;
    state = enabled;
    await _storage.save(enabled);
  }
}

final tabGlassProvider = NotifierProvider<TabGlassController, bool>(
  TabGlassController.new,
);
