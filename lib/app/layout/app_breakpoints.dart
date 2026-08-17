enum WindowLayout { mobile, tablet, desktop }

abstract class AppBreakpoints {
  static const double tablet = 600;
  static const double desktop = 1024;

  static WindowLayout resolve(double width) {
    if (width >= desktop) {
      return WindowLayout.desktop;
    }
    if (width >= tablet) {
      return WindowLayout.tablet;
    }
    return WindowLayout.mobile;
  }
}
