import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Shared root navigator for services that must open a Flutter page, such as
/// scanCode invoked through the JS bridge.
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Root [ScaffoldMessenger] shared by global feedback components.
///
/// It lets repositories/controllers report a short UI notification through the
/// presentation facade without retaining an obsolete page `BuildContext`.
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// 全局根 [ProviderContainer]，在应用 bootstrap 时创建注入。
///
/// 用于后台任务、无 BuildContext 服务或在组件已销毁（如弹窗/底栏/聊天页关闭）后安全访问全局 Provider。
ProviderContainer? rootProviderContainer;

/// 安全获取全局有效 [ProviderContainer]。
///
/// 优先使用 bootstrap 注入的 [rootProviderContainer]；若未初始化，则尝试从 [rootNavigatorKey] 提取。
ProviderContainer? get globalProviderContainer {
  if (rootProviderContainer != null) return rootProviderContainer;
  final ctx = rootNavigatorKey.currentContext;
  if (ctx != null) {
    try {
      return ProviderScope.containerOf(ctx, listen: false);
    } catch (_) {}
  }
  return null;
}

/// 聊天导航防重入保护工具类
class SafeChatNavigator {
  static int _lastNavigatedTime = 0;
  static bool _isNavigating = false;

  /// 安全跳转聊天页面，防止快速连击或短时间内重复 push 造成页面栈堆叠
  static Future<T?> pushChat<T>(
    BuildContext context,
    String location, {
    Object? extra,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_isNavigating || now - _lastNavigatedTime < 400) {
      debugPrint(
        '[ChatTrace] 🛑 SafeChatNavigator throttled navigation | '
        'elapsed=${now - _lastNavigatedTime}ms | location=$location',
      );
      return null;
    }
    _isNavigating = true;
    _lastNavigatedTime = now;
    try {
      return await GoRouter.of(context).push<T>(location, extra: extra);
    } finally {
      _isNavigating = false;
    }
  }
}

