import 'package:flutter/material.dart';

/// Centralized color palette for GotoIM.
///
/// Provides coordinated Light & Dark color definitions, semantic status
/// colors, and curated avatar gradient pairings.
abstract final class AppColors {
  // Light Primary & Secondary
  static const Color lightPrimary = Color(0xFF1E6ED8);
  static const Color lightOnPrimary = Colors.white;
  static const Color lightPrimaryContainer = Color(0xFFDCE8FD);
  static const Color lightOnPrimaryContainer = Color(0xFF001B3E);

  static const Color lightSecondary = Color(0xFF4A607A);
  static const Color lightOnSecondary = Colors.white;
  static const Color lightSecondaryContainer = Color(0xFFD6E4F7);
  static const Color lightOnSecondaryContainer = Color(0xFF061D33);

  static const Color lightTertiary = Color(0xFF6B5778);
  static const Color lightOnTertiary = Colors.white;
  static const Color lightTertiaryContainer = Color(0xFFF3DAFF);
  static const Color lightOnTertiaryContainer = Color(0xFF251432);

  // Light Surfaces & Backgrounds
  static const Color lightSurface = Color(0xFFF8FAFC);
  static const Color lightOnSurface = Color(0xFF0F172A);
  static const Color lightSurfaceDim = Color(0xFFD9E2EC);
  static const Color lightSurfaceBright = Colors.white;
  static const Color lightSurfaceContainerLowest = Colors.white;
  static const Color lightSurfaceContainerLow = Color(0xFFF1F5F9);
  static const Color lightSurfaceContainer = Color(0xFFE2E8F0);
  static const Color lightSurfaceContainerHigh = Color(0xFFCBD5E1);
  static const Color lightSurfaceContainerHighest = Color(0xFF94A3B8);

  static const Color lightOutline = Color(0xFF94A3B8);
  static const Color lightOutlineVariant = Color(0xFFCBD5E1);

  // Dark Primary & Secondary
  static const Color darkPrimary = Color(0xFF60A5FA);
  static const Color darkOnPrimary = Color(0xFF002B5C);
  static const Color darkPrimaryContainer = Color(0xFF1E40AF);
  static const Color darkOnPrimaryContainer = Color(0xFFDBEAFE);

  static const Color darkSecondary = Color(0xFF94A3B8);
  static const Color darkOnSecondary = Color(0xFF0F172A);
  static const Color darkSecondaryContainer = Color(0xFF334155);
  static const Color darkOnSecondaryContainer = Color(0xFFE2E8F0);

  static const Color darkTertiary = Color(0xFFC084FC);
  static const Color darkOnTertiary = Color(0xFF3B0764);
  static const Color darkTertiaryContainer = Color(0xFF581C87);
  static const Color darkOnTertiaryContainer = Color(0xFFF3E8FF);

  // Dark Surfaces & Backgrounds (Deep Slate / Tech Navy)
  static const Color darkSurface = Color(0xFF0F172A);
  static const Color darkOnSurface = Color(0xFFF8FAFC);
  static const Color darkSurfaceDim = Color(0xFF0B1120);
  static const Color darkSurfaceBright = Color(0xFF1E293B);
  static const Color darkSurfaceContainerLowest = Color(0xFF090D16);
  static const Color darkSurfaceContainerLow = Color(0xFF131D31);
  static const Color darkSurfaceContainer = Color(0xFF1E293B);
  static const Color darkSurfaceContainerHigh = Color(0xFF28354A);
  static const Color darkSurfaceContainerHighest = Color(0xFF334155);

  static const Color darkOutline = Color(0xFF475569);
  static const Color darkOutlineVariant = Color(0xFF334155);

  // Status & Semantic Colors
  static const Color success = Color(0xFF10B981);
  static const Color successContainer = Color(0xFFD1FAE5);
  static const Color onSuccessContainer = Color(0xFF065F46);

  static const Color warning = Color(0xFFF59E0B);
  static const Color warningContainer = Color(0xFFFEF3C7);
  static const Color onWarningContainer = Color(0xFF92400E);

  static const Color error = Color(0xFFEF4444);
  static const Color errorContainer = Color(0xFFFEE2E2);
  static const Color onErrorContainer = Color(0xFF991B1B);

  static const Color info = Color(0xFF0EA5E9);
  static const Color infoContainer = Color(0xFFE0F2FE);
  static const Color onInfoContainer = Color(0xFF075985);

  // IM Specific Accent Badges
  static const Color mentionBadge = Color(0xFFE11D48); // @我 tag
  static const Color followBadge = Color(0xFFA855F7); // 关注 tag
  static const Color onlineGreen = Color(0xFF22C55E);

  // Avatar Gradient Palettes (Aesthetic pairs for name initial fallback)
  static const List<List<Color>> avatarGradients = [
    [Color(0xFF3B82F6), Color(0xFF1D4ED8)], // Blue
    [Color(0xFF8B5CF6), Color(0xFF6D28D9)], // Purple
    [Color(0xFFEC4899), Color(0xFFBE185D)], // Pink
    [Color(0xFF10B981), Color(0xFF047857)], // Emerald
    [Color(0xFFF59E0B), Color(0xFFD97706)], // Amber
    [Color(0xFF06B6D4), Color(0xFF0E7490)], // Cyan
    [Color(0xFF6366F1), Color(0xFF4338CA)], // Indigo
    [Color(0xFF14B8A6), Color(0xFF0F766E)], // Teal
    [Color(0xFFF97316), Color(0xFFC2410C)], // Orange
    [Color(0xFF64748B), Color(0xFF334155)], // Slate
  ];
}
