import 'package:flutter/material.dart';

/// 通用对话框的外层路由参数。
///
/// 仅负责弹层行为；真实业务确认、删除、表单提交等仍应由调用页面的
/// Controller / Repository 完成，避免把业务逻辑沉入全局 UI 组件。
@immutable
class AppModalOptions {
  /// Creates modal route options. All values map to Flutter's dialog route.
  const AppModalOptions({
    this.barrierDismissible = true,
    this.useRootNavigator = true,
    this.barrierColor,
    this.barrierLabel,
    this.useSafeArea = true,
    this.routeSettings,
    this.anchorPoint,
    this.traversalEdgeBehavior,
    this.requestFocus,
    this.animationStyle,
  });

  /// 是否允许点击遮罩或按返回键关闭。破坏性操作确认通常设为 `false`。
  final bool barrierDismissible;

  /// 是否显示在根 Navigator。默认 `true`，可跨 Tab / 嵌套路由正确遮罩。
  final bool useRootNavigator;

  /// 遮罩颜色；不传使用 Material 默认颜色。
  final Color? barrierColor;

  /// 无障碍服务读出的遮罩描述。
  final String? barrierLabel;

  /// 是否避开系统状态栏、刘海和底部手势区。
  final bool useSafeArea;

  /// 路由名称与参数，用于埋点、调试和 Widget Test 定位。
  final RouteSettings? routeSettings;

  /// 大屏折叠设备上用于选择对话框所在子屏幕的锚点。
  final Offset? anchorPoint;

  /// 焦点遍历抵达末端时的行为；默认交给 Flutter。
  final TraversalEdgeBehavior? traversalEdgeBehavior;

  /// 打开后是否主动请求焦点。表单类弹层一般保持默认值。
  final bool? requestFocus;

  /// 打开、关闭动画；可用于测试中的无动画场景。
  final AnimationStyle? animationStyle;
}

/// 展示可返回任意结果的统一 Modal。
///
/// 关闭时使用 `Navigator.pop(modalContext, result)` 返回结果。适用于自定义
/// 表单、预览、选择器等；简单确认操作优先使用 [showConfirmModal]。
Future<T?> showModal<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  AppModalOptions options = const AppModalOptions(),
}) => showDialog<T>(
  context: context,
  builder: builder,
  barrierDismissible: options.barrierDismissible,
  useRootNavigator: options.useRootNavigator,
  barrierColor: options.barrierColor,
  barrierLabel: options.barrierLabel,
  useSafeArea: options.useSafeArea,
  routeSettings: options.routeSettings,
  anchorPoint: options.anchorPoint,
  traversalEdgeBehavior: options.traversalEdgeBehavior,
  requestFocus: options.requestFocus,
  animationStyle: options.animationStyle,
);

/// 展示统一的确认弹层；返回 `true` 表示用户确认，`false` 或 `null` 表示取消。
///
/// [isDestructive] 会使用 error 色强调删除、退出等不可逆操作；[onConfirmed]
/// 应在调用方 await 返回 `true` 后执行，以防止弹窗持有异步业务状态。
Future<bool?> showConfirmModal({
  required BuildContext context,
  required String title,
  required String message,
  String confirmText = '确认',
  String cancelText = '取消',
  bool isDestructive = false,
  AppModalOptions options = const AppModalOptions(),
}) => showModal<bool>(
  context: context,
  options: options,
  builder: (modalContext) {
    final colors = Theme.of(modalContext).colorScheme;
    return AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(modalContext, false),
          child: Text(cancelText),
        ),
        FilledButton(
          style:
              isDestructive
                  ? FilledButton.styleFrom(
                    backgroundColor: colors.error,
                    foregroundColor: colors.onError,
                  )
                  : null,
          onPressed: () => Navigator.pop(modalContext, true),
          child: Text(confirmText),
        ),
      ],
    );
  },
);
