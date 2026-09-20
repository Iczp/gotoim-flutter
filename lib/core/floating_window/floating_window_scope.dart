import 'package:flutter/widgets.dart';

import 'floating_window_manager.dart';

class FloatingWindowScope extends InheritedWidget {
  const FloatingWindowScope({
    super.key,
    required this.manager,
    required super.child,
  });
  final FloatingWindowManager manager;

  static FloatingWindowManager of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<FloatingWindowScope>()!
          .manager;

  static FloatingWindowManager? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<FloatingWindowScope>()
          ?.manager;

  @override
  bool updateShouldNotify(FloatingWindowScope oldWidget) =>
      manager != oldWidget.manager;
}
