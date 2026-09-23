import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/theme/app_layout_settings_controller.dart';
import 'package:gotoim_flutter/core/theme/app_theme.dart';
import 'package:gotoim_flutter/core/theme/app_theme_tokens.dart';

void main() {
  group('AppLayoutSettings', () {
    test('default values match user specifications', () {
      const settings = AppLayoutSettings();
      expect(settings.pagePaddingHorizontal, 12.0);
      expect(settings.pagePaddingVertical, 8.0);
      expect(settings.cardRadius, 12.0);
      expect(settings.dividerThickness, 0.33);
    });

    test('applyTo updates AppThemeTokens layout properties', () {
      const settings = AppLayoutSettings(
        pagePaddingHorizontal: 16.0,
        pagePaddingVertical: 10.0,
        cardRadius: 18.0,
        dividerThickness: 0.5,
      );

      final tokens = settings.applyTo(AppThemeTokens.light());
      expect(tokens.pagePaddingHorizontal, 16.0);
      expect(tokens.pagePaddingVertical, 10.0);
      expect(tokens.cardRadius, 18.0);
      expect(tokens.dividerThickness, 0.5);
      expect(tokens.pagePadding, const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0));
      expect(tokens.cardBorderRadius, BorderRadius.circular(18.0));
      expect(tokens.dividerBorderSide.width, 0.5);
    });

    test('toJson and fromJson serialize and deserialize accurately', () {
      const original = AppLayoutSettings(
        pagePaddingHorizontal: 14.0,
        pagePaddingVertical: 6.0,
        cardRadius: 10.0,
        dividerThickness: 0.25,
      );

      final json = original.toJson();
      final restored = AppLayoutSettings.fromJson(json);

      expect(restored.pagePaddingHorizontal, 14.0);
      expect(restored.pagePaddingVertical, 6.0);
      expect(restored.cardRadius, 10.0);
      expect(restored.dividerThickness, 0.25);
    });

    test('AppTheme integrates layoutSettings into ThemeData', () {
      const customSettings = AppLayoutSettings(
        pagePaddingHorizontal: 20.0,
        pagePaddingVertical: 12.0,
        cardRadius: 14.0,
        dividerThickness: 0.4,
      );

      final theme = AppTheme.lightTheme(layoutSettings: customSettings);
      final tokens = theme.extension<AppThemeTokens>();

      expect(tokens, isNotNull);
      expect(tokens!.pagePaddingHorizontal, 20.0);
      expect(tokens.pagePaddingVertical, 12.0);
      expect(tokens.cardRadius, 14.0);
      expect(tokens.dividerThickness, 0.4);
      expect(theme.dividerTheme.thickness, 0.4);
      expect(theme.cardTheme.margin, const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0));
    });
  });
}
