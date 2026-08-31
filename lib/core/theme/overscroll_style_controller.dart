import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Selects how scroll views behave when dragged past their bounds.
enum OverscrollStyle { platform, bouncing, stretch }

extension OverscrollStyleInfo on OverscrollStyle {
  String get label => switch (this) {
    OverscrollStyle.platform => '跟随平台',
    OverscrollStyle.bouncing => 'iOS 回弹',
    OverscrollStyle.stretch => '拉伸效果',
  };
}

abstract class OverscrollStyleStorage {
  Future<OverscrollStyle> read();
  Future<void> save(OverscrollStyle style);
}

class SecureOverscrollStyleStorage implements OverscrollStyleStorage {
  SecureOverscrollStyleStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'gotoim.overscroll-style.v1';
  final FlutterSecureStorage _storage;
  OverscrollStyle? _cached;

  @override
  Future<OverscrollStyle> read() async {
    if (_cached != null) return _cached!;
    try {
      final raw = await _storage.read(key: _key);
      _cached = OverscrollStyle.values.firstWhere(
        (style) => style.name == raw,
        orElse: () => OverscrollStyle.platform,
      );
      return _cached!;
    } catch (_) {
      return OverscrollStyle.platform;
    }
  }

  @override
  Future<void> save(OverscrollStyle style) async {
    _cached = style;
    try {
      await _storage.write(key: _key, value: style.name);
    } catch (_) {}
  }
}

final overscrollStyleStorageProvider = Provider<OverscrollStyleStorage>(
  (ref) => SecureOverscrollStyleStorage(),
);

class OverscrollStyleController extends Notifier<OverscrollStyle> {
  late final OverscrollStyleStorage _storage;
  bool _manuallySet = false;

  @override
  OverscrollStyle build() {
    _storage = ref.watch(overscrollStyleStorageProvider);
    _manuallySet = false;
    _restore();
    return OverscrollStyle.platform;
  }

  Future<void> _restore() async {
    final saved = await _storage.read();
    if (!_manuallySet) state = saved;
  }

  Future<void> setStyle(OverscrollStyle style) async {
    _manuallySet = true;
    if (state == style) return;
    state = style;
    await _storage.save(style);
  }
}

final overscrollStyleControllerProvider =
    NotifierProvider<OverscrollStyleController, OverscrollStyle>(
      OverscrollStyleController.new,
    );

final overscrollStyleProvider = Provider<OverscrollStyle>(
  (ref) => ref.watch(overscrollStyleControllerProvider),
);
