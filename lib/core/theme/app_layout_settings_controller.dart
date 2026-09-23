import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_theme_tokens.dart';

/// 布局与几何规范配置（边距、倒角、分割线粗细）
class AppLayoutSettings {
  const AppLayoutSettings({
    this.pagePaddingHorizontal = defaultPagePaddingHorizontal,
    this.pagePaddingVertical = defaultPagePaddingVertical,
    this.cardRadius = defaultCardRadius,
    this.dividerThickness = defaultDividerThickness,
  });

  static const double defaultPagePaddingHorizontal = 12.0;
  static const double defaultPagePaddingVertical = 8.0;
  static const double defaultCardRadius = 12.0;
  static const double defaultDividerThickness = 0.33;

  /// 默认页面左右内边距 / 外边距（一般情况 左右 12）
  final double pagePaddingHorizontal;

  /// 默认页面上下内边距 / 外边距（一般情况 上下 8）
  final double pagePaddingVertical;

  /// 统一卡片与容器倒角圆角（默认 12）
  final double cardRadius;

  /// 统一分隔线条高度/粗细（默认 0.33）
  final double dividerThickness;

  AppThemeTokens applyTo(AppThemeTokens tokens) => tokens.copyWith(
        pagePaddingHorizontal: pagePaddingHorizontal,
        pagePaddingVertical: pagePaddingVertical,
        cardRadius: cardRadius,
        dividerThickness: dividerThickness,
      );

  AppLayoutSettings copyWith({
    double? pagePaddingHorizontal,
    double? pagePaddingVertical,
    double? cardRadius,
    double? dividerThickness,
  }) =>
      AppLayoutSettings(
        pagePaddingHorizontal:
            pagePaddingHorizontal ?? this.pagePaddingHorizontal,
        pagePaddingVertical: pagePaddingVertical ?? this.pagePaddingVertical,
        cardRadius: cardRadius ?? this.cardRadius,
        dividerThickness: dividerThickness ?? this.dividerThickness,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'pagePaddingHorizontal': pagePaddingHorizontal,
        'pagePaddingVertical': pagePaddingVertical,
        'cardRadius': cardRadius,
        'dividerThickness': dividerThickness,
      };

  factory AppLayoutSettings.fromJson(Map<String, dynamic> json) =>
      AppLayoutSettings(
        pagePaddingHorizontal: (json['pagePaddingHorizontal'] as num?)?.toDouble() ??
            defaultPagePaddingHorizontal,
        pagePaddingVertical: (json['pagePaddingVertical'] as num?)?.toDouble() ??
            defaultPagePaddingVertical,
        cardRadius:
            (json['cardRadius'] as num?)?.toDouble() ?? defaultCardRadius,
        dividerThickness: (json['dividerThickness'] as num?)?.toDouble() ??
            defaultDividerThickness,
      );
}

class AppLayoutSettingsController extends Notifier<AppLayoutSettings> {
  static const _storageKey = 'app_layout_geometry_settings_v1';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  AppLayoutSettings build() {
    _load();
    return const AppLayoutSettings();
  }

  Future<void> _load() async {
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw == null || raw.isEmpty) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      state = AppLayoutSettings.fromJson(json);
    } catch (_) {
      // 容错回退为默认配置
    }
  }

  Future<void> update(AppLayoutSettings next) async {
    state = next;
    try {
      await _storage.write(
        key: _storageKey,
        value: jsonEncode(next.toJson()),
      );
    } catch (_) {
      // 存储异常不影响内存即时生效
    }
  }

  Future<void> reset() async {
    state = const AppLayoutSettings();
    try {
      await _storage.delete(key: _storageKey);
    } catch (_) {}
  }
}

final appLayoutSettingsProvider =
    NotifierProvider<AppLayoutSettingsController, AppLayoutSettings>(
  AppLayoutSettingsController.new,
);
