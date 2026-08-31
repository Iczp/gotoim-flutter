import 'package:flutter/material.dart';

/// Centralized typography specifications for GotoIM.
///
/// Follows Material 3 text scales with refined font weights and line heights
/// optimized for modern cross-platform chat and productivity apps.
abstract final class AppTypography {
  static const TextStyle displayLarge = TextStyle(
    fontSize: 57,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.25,
    height: 1.12,
  );

  static const TextStyle displayMedium = TextStyle(
    fontSize: 45,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    height: 1.16,
  );

  static const TextStyle displaySmall = TextStyle(
    fontSize: 36,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    height: 1.22,
  );

  static const TextStyle headlineLarge = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    height: 1.25,
  );

  static const TextStyle headlineMedium = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    height: 1.29,
  );

  static const TextStyle headlineSmall = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    height: 1.33,
  );

  static const TextStyle titleLarge = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    height: 1.27,
  );

  static const TextStyle titleMedium = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.15,
    height: 1.5,
  );

  static const TextStyle titleSmall = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
    height: 1.43,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.5,
    height: 1.5,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.25,
    height: 1.43,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.4,
    height: 1.33,
  );

  static const TextStyle labelLarge = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
    height: 1.43,
  );

  static const TextStyle labelMedium = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
    height: 1.33,
  );

  static const TextStyle labelSmall = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
    height: 1.45,
  );

  /// Create a complete TextTheme based on a brightness/color.
  static TextTheme createTextTheme(Color onSurfaceColor) {
    return TextTheme(
      displayLarge: displayLarge.copyWith(color: onSurfaceColor),
      displayMedium: displayMedium.copyWith(color: onSurfaceColor),
      displaySmall: displaySmall.copyWith(color: onSurfaceColor),
      headlineLarge: headlineLarge.copyWith(color: onSurfaceColor),
      headlineMedium: headlineMedium.copyWith(color: onSurfaceColor),
      headlineSmall: headlineSmall.copyWith(color: onSurfaceColor),
      titleLarge: titleLarge.copyWith(color: onSurfaceColor),
      titleMedium: titleMedium.copyWith(color: onSurfaceColor),
      titleSmall: titleSmall.copyWith(color: onSurfaceColor),
      bodyLarge: bodyLarge.copyWith(color: onSurfaceColor),
      bodyMedium: bodyMedium.copyWith(color: onSurfaceColor),
      bodySmall: bodySmall.copyWith(
        color: onSurfaceColor.withValues(alpha: 0.7),
      ),
      labelLarge: labelLarge.copyWith(color: onSurfaceColor),
      labelMedium: labelMedium.copyWith(color: onSurfaceColor),
      labelSmall: labelSmall.copyWith(
        color: onSurfaceColor.withValues(alpha: 0.6),
      ),
    );
  }
}
