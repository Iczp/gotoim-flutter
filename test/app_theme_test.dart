import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/theme/app_colors.dart';
import 'package:gotoim_flutter/core/theme/app_theme.dart';
import 'package:gotoim_flutter/core/theme/app_theme_tokens.dart';
import 'package:gotoim_flutter/core/theme/theme_mode_controller.dart';
import 'package:gotoim_flutter/core/theme/theme_mode_storage.dart';

class FakeThemeModeStorage implements ThemeModeStorage {
  ThemeMode mode = ThemeMode.system;

  @override
  Future<ThemeMode> readThemeMode() async => mode;

  @override
  Future<void> saveThemeMode(ThemeMode newMode) async {
    mode = newMode;
  }
}

void main() {
  group('AppTheme Configuration', () {
    test('lightTheme provides complete Light Material 3 setup and tokens', () {
      final theme = AppTheme.lightTheme();
      expect(theme.brightness, Brightness.light);
      expect(theme.useMaterial3, isTrue);
      expect(theme.colorScheme.primary, AppColors.lightPrimary);
      expect(theme.appBarTheme.elevation, 0);

      final tokens = theme.extension<AppThemeTokens>();
      expect(tokens, isNotNull);
      expect(tokens!.sessionPinnedBackground, const Color(0xFFF1F5F9));
      expect(tokens.mentionBadgeColor, AppColors.mentionBadge);
      expect(tokens.unreadBadgeColor, AppColors.error);
      expect(tokens.glassBlurSigma, 16.0);
      expect(tokens.glassSurfaceColor, const Color(0xD9FFFFFF));
    });

    test(
      'darkTheme provides complete Dark Material 3 setup and deep navy tokens',
      () {
        final theme = AppTheme.darkTheme();
        expect(theme.brightness, Brightness.dark);
        expect(theme.useMaterial3, isTrue);
        expect(theme.colorScheme.primary, AppColors.darkPrimary);
        expect(theme.colorScheme.surface, AppColors.darkSurface);

        final tokens = theme.extension<AppThemeTokens>();
        expect(tokens, isNotNull);
        expect(tokens!.sessionPinnedBackground, const Color(0xFF1E293B));
        expect(tokens.dividerBorder, const Color(0xFF334155));
        expect(tokens.glassBlurSigma, 18.0);
        expect(tokens.glassSurfaceColor, const Color(0xB31E293B));
      },
    );
  });

  group('AppThemeTokens Extension', () {
    test(
      'getAvatarGradient returns deterministic gradient pairs for different names',
      () {
        final tokens = AppThemeTokens.light();
        final gradA = tokens.getAvatarGradient('Alice');
        final gradB = tokens.getAvatarGradient('Bob');
        final gradEmpty = tokens.getAvatarGradient('');

        expect(gradA.length, 2);
        expect(gradB.length, 2);
        expect(gradEmpty.length, 2);
        expect(gradEmpty, AppColors.avatarGradients.first);
      },
    );

    test('copyWith and lerp operate seamlessly', () {
      final light = AppThemeTokens.light();
      final dark = AppThemeTokens.dark();

      final custom = light.copyWith(sessionPinnedBackground: Colors.amber);
      expect(custom.sessionPinnedBackground, Colors.amber);
      expect(custom.dividerBorder, light.dividerBorder);

      final halfway = light.lerp(dark, 0.5) as AppThemeTokens;
      expect(halfway, isNotNull);
      expect(
        halfway.sessionPinnedBackground,
        Color.lerp(
          light.sessionPinnedBackground,
          dark.sessionPinnedBackground,
          0.5,
        ),
      );

      final lerpNull = light.lerp(null, 0.5);
      expect(identical(lerpNull, light), isTrue);
    });
  });

  group('ThemeModeController & State', () {
    test('initializes and responds to setThemeMode and toggleTheme', () async {
      final fakeStorage = FakeThemeModeStorage();
      final container = ProviderContainer(
        overrides: [themeModeStorageProvider.overrideWithValue(fakeStorage)],
      );
      addTearDown(container.dispose);

      // Initial state is system
      expect(container.read(themeModeProvider), ThemeMode.system);

      // Switch to dark
      await container
          .read(themeModeControllerProvider.notifier)
          .setThemeMode(ThemeMode.dark);
      expect(container.read(themeModeProvider), ThemeMode.dark);
      expect(fakeStorage.mode, ThemeMode.dark);

      // Toggle to light
      await container.read(themeModeControllerProvider.notifier).toggleTheme();
      expect(container.read(themeModeProvider), ThemeMode.light);
      expect(fakeStorage.mode, ThemeMode.light);

      // Toggle back to dark
      await container.read(themeModeControllerProvider.notifier).toggleTheme();
      expect(container.read(themeModeProvider), ThemeMode.dark);
    });
  });
}
