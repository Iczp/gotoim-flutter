import 'package:flutter/material.dart';

import 'app_colors.dart';

/// IM-specific custom theme tokens via Material 3 ThemeExtension.
///
/// Ensures specialized components (pinned chat backgrounds, message bubble colors,
/// badge pills, divider lines, and dynamic avatar gradients) respond seamlessly
/// to Light and Dark mode transitions without hardcoded colors.
class AppThemeTokens extends ThemeExtension<AppThemeTokens> {
  const AppThemeTokens({
    required this.sessionPinnedBackground,
    required this.dividerBorder,
    required this.headerBackground,
    required this.deviceBarBackground,
    required this.mentionBadgeColor,
    required this.unreadBadgeColor,
    required this.followBadgeColor,
    required this.cardBorder,
    required this.bubbleMeBackground,
    required this.bubbleMeText,
    required this.bubbleOtherBackground,
    required this.bubbleOtherText,
    required this.cardBackground,
    required this.glassEffectColor,
    required this.glassSurfaceColor,
    required this.glassBorderColor,
    required this.glassSecondarySurface,
    required this.glassBlurSigma,
    required this.avatarGradients,
  });

  final Color sessionPinnedBackground;
  final Color dividerBorder;
  final Color headerBackground;
  final Color deviceBarBackground;
  final Color mentionBadgeColor;
  final Color unreadBadgeColor;
  final Color followBadgeColor;
  final Color cardBorder;
  final Color bubbleMeBackground;
  final Color bubbleMeText;
  final Color bubbleOtherBackground;
  final Color bubbleOtherText;
  final Color cardBackground;
  final Color glassEffectColor;
  final Color glassSurfaceColor;
  final Color glassBorderColor;
  final Color glassSecondarySurface;
  final double glassBlurSigma;
  final List<List<Color>> avatarGradients;

  /// Light theme token preset.
  factory AppThemeTokens.light() {
    return const AppThemeTokens(
      sessionPinnedBackground: Color(0xFFF1F5F9),
      dividerBorder: Color(0xFFE2E8F0),
      headerBackground: Colors.white,
      deviceBarBackground: Color(0xFFF1F5F9),
      mentionBadgeColor: AppColors.mentionBadge,
      unreadBadgeColor: AppColors.error,
      followBadgeColor: AppColors.followBadge,
      cardBorder: Color(0xFFE2E8F0),
      bubbleMeBackground: Color(0xFF1E6ED8),
      bubbleMeText: Colors.white,
      bubbleOtherBackground: Color(0xFFF1F5F9),
      bubbleOtherText: Color(0xFF0F172A),
      cardBackground: Colors.white,
      glassEffectColor: Color(0xCCFFFFFF),
      glassSurfaceColor: Color(0xD9FFFFFF),
      glassBorderColor: Color(0x66FFFFFF),
      glassSecondarySurface: Color(0xB3F1F5F9),
      glassBlurSigma: 16.0,
      avatarGradients: AppColors.avatarGradients,
    );
  }

  /// Dark theme token preset.
  factory AppThemeTokens.dark() {
    return const AppThemeTokens(
      sessionPinnedBackground: Color(0xFF1E293B),
      dividerBorder: Color(0xFF334155),
      headerBackground: Color(0xFF0F172A),
      deviceBarBackground: Color(0xFF1E293B),
      mentionBadgeColor: Color(0xFFF43F5E),
      unreadBadgeColor: Color(0xFFEF4444),
      followBadgeColor: Color(0xFFC084FC),
      cardBorder: Color(0xFF334155),
      bubbleMeBackground: Color(0xFF2563EB),
      bubbleMeText: Colors.white,
      bubbleOtherBackground: Color(0xFF1E293B),
      bubbleOtherText: Color(0xFFF8FAFC),
      cardBackground: Color(0xFF1E293B),
      glassEffectColor: Color(0xCC0F172A),
      glassSurfaceColor: Color(0xB31E293B),
      glassBorderColor: Color(0x26FFFFFF),
      glassSecondarySurface: Color(0x800F172A),
      glassBlurSigma: 18.0,
      avatarGradients: AppColors.avatarGradients,
    );
  }

  /// Resolve a curated 2-color aesthetic gradient for an avatar based on a name string.
  List<Color> getAvatarGradient(String name) {
    if (name.isEmpty) return avatarGradients.first;
    final hash = name.codeUnits.fold<int>(0, (sum, unit) => sum + unit);
    final index = hash.abs() % avatarGradients.length;
    return avatarGradients[index];
  }

  @override
  AppThemeTokens copyWith({
    Color? sessionPinnedBackground,
    Color? dividerBorder,
    Color? headerBackground,
    Color? deviceBarBackground,
    Color? mentionBadgeColor,
    Color? unreadBadgeColor,
    Color? followBadgeColor,
    Color? cardBorder,
    Color? bubbleMeBackground,
    Color? bubbleMeText,
    Color? bubbleOtherBackground,
    Color? bubbleOtherText,
    Color? cardBackground,
    Color? glassEffectColor,
    Color? glassSurfaceColor,
    Color? glassBorderColor,
    Color? glassSecondarySurface,
    double? glassBlurSigma,
    List<List<Color>>? avatarGradients,
  }) {
    return AppThemeTokens(
      sessionPinnedBackground:
          sessionPinnedBackground ?? this.sessionPinnedBackground,
      dividerBorder: dividerBorder ?? this.dividerBorder,
      headerBackground: headerBackground ?? this.headerBackground,
      deviceBarBackground: deviceBarBackground ?? this.deviceBarBackground,
      mentionBadgeColor: mentionBadgeColor ?? this.mentionBadgeColor,
      unreadBadgeColor: unreadBadgeColor ?? this.unreadBadgeColor,
      followBadgeColor: followBadgeColor ?? this.followBadgeColor,
      cardBorder: cardBorder ?? this.cardBorder,
      bubbleMeBackground: bubbleMeBackground ?? this.bubbleMeBackground,
      bubbleMeText: bubbleMeText ?? this.bubbleMeText,
      bubbleOtherBackground:
          bubbleOtherBackground ?? this.bubbleOtherBackground,
      bubbleOtherText: bubbleOtherText ?? this.bubbleOtherText,
      cardBackground: cardBackground ?? this.cardBackground,
      glassEffectColor: glassEffectColor ?? this.glassEffectColor,
      glassSurfaceColor: glassSurfaceColor ?? this.glassSurfaceColor,
      glassBorderColor: glassBorderColor ?? this.glassBorderColor,
      glassSecondarySurface:
          glassSecondarySurface ?? this.glassSecondarySurface,
      glassBlurSigma: glassBlurSigma ?? this.glassBlurSigma,
      avatarGradients: avatarGradients ?? this.avatarGradients,
    );
  }

  @override
  ThemeExtension<AppThemeTokens> lerp(
    covariant ThemeExtension<AppThemeTokens>? other,
    double t,
  ) {
    if (other is! AppThemeTokens) return this;
    return AppThemeTokens(
      sessionPinnedBackground:
          Color.lerp(
            sessionPinnedBackground,
            other.sessionPinnedBackground,
            t,
          )!,
      dividerBorder: Color.lerp(dividerBorder, other.dividerBorder, t)!,
      headerBackground:
          Color.lerp(headerBackground, other.headerBackground, t)!,
      deviceBarBackground:
          Color.lerp(deviceBarBackground, other.deviceBarBackground, t)!,
      mentionBadgeColor:
          Color.lerp(mentionBadgeColor, other.mentionBadgeColor, t)!,
      unreadBadgeColor:
          Color.lerp(unreadBadgeColor, other.unreadBadgeColor, t)!,
      followBadgeColor:
          Color.lerp(followBadgeColor, other.followBadgeColor, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      bubbleMeBackground:
          Color.lerp(bubbleMeBackground, other.bubbleMeBackground, t)!,
      bubbleMeText: Color.lerp(bubbleMeText, other.bubbleMeText, t)!,
      bubbleOtherBackground:
          Color.lerp(bubbleOtherBackground, other.bubbleOtherBackground, t)!,
      bubbleOtherText: Color.lerp(bubbleOtherText, other.bubbleOtherText, t)!,
      cardBackground: Color.lerp(cardBackground, other.cardBackground, t)!,
      glassEffectColor:
          Color.lerp(glassEffectColor, other.glassEffectColor, t)!,
      glassSurfaceColor:
          Color.lerp(glassSurfaceColor, other.glassSurfaceColor, t)!,
      glassBorderColor:
          Color.lerp(glassBorderColor, other.glassBorderColor, t)!,
      glassSecondarySurface:
          Color.lerp(glassSecondarySurface, other.glassSecondarySurface, t)!,
      glassBlurSigma:
          glassBlurSigma + (other.glassBlurSigma - glassBlurSigma) * t,
      avatarGradients: t < 0.5 ? avatarGradients : other.avatarGradients,
    );
  }
}

/// Handy extension to retrieve [AppThemeTokens] from [BuildContext].
extension AppThemeContextExtension on BuildContext {
  AppThemeTokens get appTokens =>
      Theme.of(this).extension<AppThemeTokens>() ?? AppThemeTokens.light();
}
