import 'package:flutter/widgets.dart';
import 'statistic_event_names.dart';
import 'statistic_page_names.dart';
import 'statistic_service.dart';

/// 自动页面访问与停留时长统计 RouteObserver
class StatisticRouteObserver extends NavigatorObserver {
  StatisticRouteObserver();

  final Map<Route<dynamic>, ({String pageName, DateTime enterTime})> _routeStack =
      <Route<dynamic>, ({String pageName, DateTime enterTime})>{};

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (previousRoute != null) {
      _handlePageLeave(previousRoute);
    }
    _handlePageView(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _handlePageLeave(route);
    if (previousRoute != null) {
      _handlePageView(previousRoute);
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (oldRoute != null) {
      _handlePageLeave(oldRoute);
    }
    if (newRoute != null) {
      _handlePageView(newRoute);
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _handlePageLeave(route);
  }

  void _handlePageView(Route<dynamic> route) {
    final name = _extractRouteName(route);
    if (name == null || name.isEmpty) return;

    final pageName = StatisticPageNames.resolvePageName(name);
    _routeStack[route] = (pageName: pageName, enterTime: DateTime.now());

    StatisticService.instance.track(
      StatisticEventNames.pageView,
      page: pageName,
    );
  }

  void _handlePageLeave(Route<dynamic> route) {
    final entry = _routeStack.remove(route);
    if (entry == null) return;

    final durationSeconds =
        DateTime.now().difference(entry.enterTime).inSeconds;

    StatisticService.instance.track(
      StatisticEventNames.pageLeave,
      page: entry.pageName,
      properties: <String, dynamic>{
        'durationSeconds': durationSeconds < 0 ? 0 : durationSeconds,
      },
    );
  }

  String? _extractRouteName(Route<dynamic> route) {
    // 忽略 Dialog、BottomSheet、Popup 等临时非全屏路由
    if (route is! PageRoute) return null;
    return route.settings.name;
  }
}
