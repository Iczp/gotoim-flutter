import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 预设字体缩放档位
enum FontScaleLevel {
  small(0.875, '小'),
  standard(1.0, '标准'),
  medium(1.125, '中'),
  large(1.25, '大'),
  extraLarge(1.375, '特大');

  const FontScaleLevel(this.scale, this.label);

  final double scale;
  final String label;

  /// 根据数值寻找最接近的档位
  static FontScaleLevel fromScale(double scale) {
    var closest = FontScaleLevel.standard;
    var minDiff = double.infinity;
    for (final level in FontScaleLevel.values) {
      final diff = (level.scale - scale).abs();
      if (diff < minDiff) {
        minDiff = diff;
        closest = level;
      }
    }
    return closest;
  }
}

/// 存储抽象
abstract class FontScaleStorage {
  Future<double> readFontScale();
  Future<void> saveFontScale(double scale);
}

/// SecureStorage 持久化实现
class SecureFontScaleStorage implements FontScaleStorage {
  SecureFontScaleStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _fontScaleKey = 'gotoim.font-scale.v1';
  final FlutterSecureStorage _storage;
  double? _cached;

  @override
  Future<double> readFontScale() async {
    if (_cached != null) return _cached!;
    try {
      final val = await _storage.read(key: _fontScaleKey);
      if (val != null) {
        final parsed = double.tryParse(val);
        if (parsed != null && parsed >= 0.75 && parsed <= 1.5) {
          _cached = parsed;
          return parsed;
        }
      }
    } catch (_) {}
    return FontScaleLevel.standard.scale;
  }

  @override
  Future<void> saveFontScale(double scale) async {
    _cached = scale;
    try {
      await _storage.write(key: _fontScaleKey, value: scale.toString());
    } catch (_) {}
  }
}

/// Storage Provider
final fontScaleStorageProvider = Provider<FontScaleStorage>(
  (ref) => SecureFontScaleStorage(),
);

/// 字体大小缩放控制器
class FontScaleController extends Notifier<double> {
  late final FontScaleStorage _storage;
  bool _manuallySet = false;

  @override
  double build() {
    _storage = ref.watch(fontScaleStorageProvider);
    _manuallySet = false;
    _restore();
    return FontScaleLevel.standard.scale;
  }

  Future<void> _restore() async {
    final savedScale = await _storage.readFontScale();
    if (!_manuallySet) {
      state = savedScale;
    }
  }

  /// 设置新的字体缩放比例
  Future<void> setScale(double scale) async {
    _manuallySet = true;
    if ((state - scale).abs() < 0.001) return;
    state = scale;
    await _storage.saveFontScale(scale);
  }

  /// 切换至下一个缩放档位
  Future<void> setLevel(FontScaleLevel level) async {
    await setScale(level.scale);
  }

  /// 恢复默认标准比例 (1.0)
  Future<void> reset() async {
    await setLevel(FontScaleLevel.standard);
  }
}

/// Controller Provider
final fontScaleControllerProvider =
    NotifierProvider<FontScaleController, double>(FontScaleController.new);

/// 便捷监听当前字体缩放比例的 Provider
final fontScaleProvider = Provider<double>((ref) {
  return ref.watch(fontScaleControllerProvider);
});
