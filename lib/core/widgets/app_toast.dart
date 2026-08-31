import 'package:flutter/material.dart';

import '../../app/app_navigation.dart';

/// Toast 语义类型，决定默认图标与颜色。
enum ToastType { success, error, warning, info }

/// 全局短提示的展示参数。
@immutable
class ToastOptions {
  /// Creates toast options. Defaults are suitable for lightweight feedback.
  const ToastOptions({
    this.type = ToastType.info,
    this.duration = const Duration(seconds: 2),
    this.actionLabel,
    this.onAction,
    this.icon,
    this.closePrevious = true,
  });

  /// 提示语义。成功、失败、警告和普通信息分别有默认图标与主题颜色。
  final ToastType type;

  /// 自动消失时间。错误信息建议至少 3 秒，极短提示可使用 1 秒。
  final Duration duration;

  /// 可选操作按钮文字，例如「撤销」「重试」。必须与 [onAction] 一起提供。
  final String? actionLabel;

  /// 点击可选操作按钮后的回调。回调中应自行处理异步错误。
  final VoidCallback? onAction;

  /// 覆盖默认图标；传入 `null` 使用由 [type] 决定的图标。
  final IconData? icon;

  /// 显示前是否先移除上一条提示，避免高频事件堆积过时 SnackBar。
  final bool closePrevious;
}

/// 展示全局短提示，不需要页面 [BuildContext]。
///
/// 返回 `false` 说明应用尚未挂载根 ScaffoldMessenger，此时不会抛异常。
/// 适合 Controller 完成操作后的轻提示；表单字段错误仍应直接显示在字段附近。
bool showToast(String message, {ToastOptions options = const ToastOptions()}) {
  final messenger = rootScaffoldMessengerKey.currentState;
  if (messenger == null || message.trim().isEmpty) return false;
  if (options.closePrevious) messenger.hideCurrentSnackBar();
  final scheme = Theme.of(messenger.context).colorScheme;
  final style = _ToastStyle.from(options.type, scheme);
  messenger.showSnackBar(
    SnackBar(
      duration: options.duration,
      backgroundColor: style.backgroundColor,
      content: Row(
        children: <Widget>[
          Icon(
            options.icon ?? style.icon,
            color: style.foregroundColor,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: style.foregroundColor),
            ),
          ),
        ],
      ),
      action:
          options.actionLabel == null || options.onAction == null
              ? null
              : SnackBarAction(
                label: options.actionLabel!,
                onPressed: options.onAction!,
              ),
    ),
  );
  return true;
}

/// 快捷成功提示。
bool showSuccessToast(
  String message, {
  ToastOptions options = const ToastOptions(),
}) => showToast(
  message,
  options: ToastOptions(
    type: ToastType.success,
    duration: options.duration,
    actionLabel: options.actionLabel,
    onAction: options.onAction,
    icon: options.icon,
    closePrevious: options.closePrevious,
  ),
);

/// 快捷失败提示。
bool showErrorToast(
  String message, {
  ToastOptions options = const ToastOptions(),
}) => showToast(
  message,
  options: ToastOptions(
    type: ToastType.error,
    duration: options.duration,
    actionLabel: options.actionLabel,
    onAction: options.onAction,
    icon: options.icon,
    closePrevious: options.closePrevious,
  ),
);

/// 快捷警告提示。
bool showWarningToast(
  String message, {
  ToastOptions options = const ToastOptions(),
}) => showToast(
  message,
  options: ToastOptions(
    type: ToastType.warning,
    duration: options.duration,
    actionLabel: options.actionLabel,
    onAction: options.onAction,
    icon: options.icon,
    closePrevious: options.closePrevious,
  ),
);

/// 快捷普通信息提示。
bool showInfoToast(
  String message, {
  ToastOptions options = const ToastOptions(),
}) => showToast(
  message,
  options: ToastOptions(
    type: ToastType.info,
    duration: options.duration,
    actionLabel: options.actionLabel,
    onAction: options.onAction,
    icon: options.icon,
    closePrevious: options.closePrevious,
  ),
);

class _ToastStyle {
  const _ToastStyle(this.icon, this.backgroundColor, this.foregroundColor);
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;

  factory _ToastStyle.from(ToastType type, ColorScheme colors) =>
      switch (type) {
        ToastType.success => _ToastStyle(
          Icons.check_circle_outline,
          colors.primaryContainer,
          colors.onPrimaryContainer,
        ),
        ToastType.error => _ToastStyle(
          Icons.error_outline,
          colors.errorContainer,
          colors.onErrorContainer,
        ),
        ToastType.warning => _ToastStyle(
          Icons.warning_amber_outlined,
          colors.tertiaryContainer,
          colors.onTertiaryContainer,
        ),
        ToastType.info => _ToastStyle(
          Icons.info_outline,
          colors.secondaryContainer,
          colors.onSecondaryContainer,
        ),
      };
}
