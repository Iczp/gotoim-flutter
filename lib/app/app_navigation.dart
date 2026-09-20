import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

