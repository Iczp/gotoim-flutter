import 'dart:ui';
import 'package:flutter/material.dart';

import '../theme/app_theme_tokens.dart';

/// Reusable high-performance frosted glass container with configurable blur,
/// specular border highlight, translucent tint, and gradient reflection.
class GlassContainer extends StatelessWidget {
  const GlassContainer({
    required this.child,
    super.key,
    this.borderRadius,
    this.blurSigma,
    this.backgroundColor,
    this.borderColor,
    this.borderWidth = 1.0,
    this.gradient,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.alignment,
    this.boxShadow,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;
  final BorderRadiusGeometry? borderRadius;
  final double? blurSigma;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderWidth;
  final Gradient? gradient;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final AlignmentGeometry? alignment;
  final List<BoxShadow>? boxShadow;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final effectiveRadius = borderRadius ?? BorderRadius.circular(16);
    final effectiveBlur = blurSigma ?? tokens.glassBlurSigma;
    final effectiveBg = backgroundColor ?? tokens.glassSurfaceColor;
    final effectiveBorder = borderColor ?? tokens.glassBorderColor;

    Widget current = Container(
      width: width,
      height: height,
      alignment: alignment,
      padding: padding,
      decoration: BoxDecoration(
        color: effectiveBg,
        gradient: gradient,
        borderRadius: effectiveRadius,
        border:
            borderWidth > 0
                ? Border.all(color: effectiveBorder, width: borderWidth)
                : null,
      ),
      child: child,
    );

    if (effectiveBlur > 0) {
      current = ClipRRect(
        borderRadius: effectiveRadius,
        clipBehavior: clipBehavior,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: effectiveBlur,
            sigmaY: effectiveBlur,
          ),
          child: current,
        ),
      );
    }

    if (boxShadow != null && boxShadow!.isNotEmpty) {
      current = Container(
        margin: margin,
        decoration: BoxDecoration(
          borderRadius: effectiveRadius,
          boxShadow: boxShadow,
        ),
        child: current,
      );
    } else if (margin != null) {
      current = Padding(padding: margin!, child: current);
    }

    return current;
  }
}

/// A modern frosted glass card component with elevation and specular rim.
class GlassCard extends StatelessWidget {
  const GlassCard({
    required this.child,
    super.key,
    this.borderRadius,
    this.blurSigma,
    this.backgroundColor,
    this.borderColor,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });

  final Widget child;
  final BorderRadiusGeometry? borderRadius;
  final double? blurSigma;
  final Color? backgroundColor;
  final Color? borderColor;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GlassContainer(
      margin: margin,
      padding: padding,
      borderRadius: borderRadius ?? BorderRadius.circular(18),
      blurSigma: blurSigma,
      backgroundColor: backgroundColor,
      borderColor: borderColor,
      borderWidth: 1.0,
      boxShadow: [
        BoxShadow(
          color:
              isDark
                  ? Colors.black.withValues(alpha: 0.35)
                  : Colors.black.withValues(alpha: 0.04),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ],
      child: child,
    );
  }
}

/// A modern frosted glass AppBar with dynamic backdrop blur.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.bottom,
    this.blurSigma,
    this.backgroundColor,
    this.borderColor,
    this.centerTitle = true,
  });

  final Widget? title;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final double? blurSigma;
  final Color? backgroundColor;
  final Color? borderColor;
  final bool centerTitle;

  @override
  Size get preferredSize {
    final bottomHeight = bottom?.preferredSize.height ?? 0.0;
    return Size.fromHeight(kToolbarHeight + bottomHeight);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final effectiveBlur = blurSigma ?? tokens.glassBlurSigma;
    final effectiveBg = backgroundColor ?? tokens.glassSurfaceColor;
    final effectiveBorder = borderColor ?? tokens.glassBorderColor;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: effectiveBlur, sigmaY: effectiveBlur),
        child: Container(
          decoration: BoxDecoration(
            color: effectiveBg,
            border: Border(
              bottom: BorderSide(color: effectiveBorder, width: 0.8),
            ),
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            leading: leading,
            title: title,
            actions: actions,
            bottom: bottom,
            centerTitle: centerTitle,
          ),
        ),
      ),
    );
  }
}
