import 'package:flutter/material.dart';

import '../theme/overscroll_style_controller.dart';

/// Uses iOS-style overscroll on every platform instead of Android's stretch.
///
/// The selected behavior is persisted in the application's appearance settings.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior({required this.style});

  final OverscrollStyle style;

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => switch (style) {
    OverscrollStyle.platform => super.buildOverscrollIndicator(
      context,
      child,
      details,
    ),
    OverscrollStyle.bouncing => child,
    OverscrollStyle.stretch => StretchingOverscrollIndicator(
      axisDirection: details.direction,
      child: child,
    ),
  };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => switch (style) {
    OverscrollStyle.platform => super.getScrollPhysics(context),
    OverscrollStyle.bouncing => const BouncingScrollPhysics(
      parent: AlwaysScrollableScrollPhysics(),
    ),
    OverscrollStyle.stretch => const ClampingScrollPhysics(
      parent: AlwaysScrollableScrollPhysics(),
    ),
  };
}
