import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Unified route transition builder for GotoIM.
class AppRouteTransition {
  AppRouteTransition._();

  /// Standard horizontal slide-in transition from right to left (default for subpages).
  static CustomTransitionPage<T> slideRight<T>({
    required BuildContext context,
    required GoRouterState state,
    required Widget child,
    Duration duration = const Duration(milliseconds: 260),
    Duration reverseDuration = const Duration(milliseconds: 220),
  }) {
    return CustomTransitionPage<T>(
      key: state.pageKey,
      child: child,
      transitionDuration: duration,
      reverseTransitionDuration: reverseDuration,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        final slideIn = Tween<Offset>(
          begin: const Offset(1.0, 0.0),
          end: Offset.zero,
        ).animate(curvedAnimation);

        final fadeIn = Tween<double>(
          begin: 0.85,
          end: 1.0,
        ).animate(curvedAnimation);

        return SlideTransition(
          position: slideIn,
          child: FadeTransition(
            opacity: fadeIn,
            child: child,
          ),
        );
      },
    );
  }

  /// Bottom sheet / modal slide-up transition.
  static CustomTransitionPage<T> slideUp<T>({
    required BuildContext context,
    required GoRouterState state,
    required Widget child,
    Duration duration = const Duration(milliseconds: 280),
    Duration reverseDuration = const Duration(milliseconds: 220),
  }) {
    return CustomTransitionPage<T>(
      key: state.pageKey,
      child: child,
      transitionDuration: duration,
      reverseTransitionDuration: reverseDuration,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        final slideUp = Tween<Offset>(
          begin: const Offset(0.0, 1.0),
          end: Offset.zero,
        ).animate(curvedAnimation);

        return SlideTransition(
          position: slideUp,
          child: child,
        );
      },
    );
  }

  /// Smooth subtle fade transition.
  static CustomTransitionPage<T> fade<T>({
    required BuildContext context,
    required GoRouterState state,
    required Widget child,
    Duration duration = const Duration(milliseconds: 200),
  }) {
    return CustomTransitionPage<T>(
      key: state.pageKey,
      child: child,
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
    );
  }
}
