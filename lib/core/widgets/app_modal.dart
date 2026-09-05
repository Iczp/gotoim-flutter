import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_navigation.dart';

/// 对话框按钮布局方式。
enum ModalActionsLayout {
  /// 自动判断（按钮少且文本简短时水平并排，文本过长或包含第 3 按钮时垂直堆叠）
  auto,

  /// 水平并排
  horizontal,

  /// 垂直堆叠
  vertical,
}

/// 弹窗过渡动画类型。
enum ModalTransitionType {
  /// Material 3 默认缩放渐变
  material3,

  /// 居中缩放放大
  scale,

  /// 纯淡入淡出
  fade,

  /// 底部向上滑入
  slideFromBottom,

  /// 顶部向下滑入
  slideFromTop,
}

/// 综合 Modal 返回结果。
@immutable
class ModalResult<T> {
  const ModalResult({
    this.confirmed = false,
    this.cancelled = false,
    this.isNeutral = false,
    this.content,
    this.checkboxValue,
    this.data,
  });

  /// 用户是否点击了确认按钮
  final bool confirmed;

  /// 用户是否点击了取消按钮、右上角关闭或遮罩
  final bool cancelled;

  /// 用户是否点击了中间态第三按钮（如“稍后提醒”、“跳过”）
  final bool isNeutral;

  /// 输入框文本（Prompt / Input 模式下有效）
  final String? content;

  /// 勾选框状态（如“不再提醒”选项）
  final bool? checkboxValue;

  /// 自定义携带的数据（如单选/多选结果）
  final T? data;

  bool get isConfirmed => confirmed;
  bool get isCancelled => cancelled;
}

/// 选项菜单项定义（ActionSheet / Radio / Checkbox）。
@immutable
class ModalActionItem<T> {
  const ModalActionItem({
    required this.title,
    this.subtitle,
    this.icon,
    this.value,
    this.isDestructive = false,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final Widget? icon;
  final T? value;
  final bool isDestructive;
  final bool enabled;
}

/// 通用对话框的外层路由与容器参数。
@immutable
class AppModalOptions {
  /// Creates modal route and container options.
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
    // 外观与容器
    this.backgroundColor,
    this.borderRadius = 20.0,
    this.maxWidth = 420.0,
    this.minWidth = 280.0,
    this.elevation = 6.0,
    this.insetPadding = const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
    this.alignment = Alignment.center,
    this.clipBehavior = Clip.antiAlias,
    // 毛玻璃与动画
    this.backdropBlur = 0.0,
    this.transitionType = ModalTransitionType.material3,
    this.transitionDuration,
    this.autoCloseDuration,
    // 交互反馈
    this.vibrate = false,
    this.playSound = false,
  });

  /// 是否允许点击遮罩或按返回键关闭。
  final bool barrierDismissible;

  /// 是否显示在根 Navigator。默认 `true`。
  final bool useRootNavigator;

  /// 遮罩颜色；不传使用主题默认半透明黑色。
  final Color? barrierColor;

  /// 无障碍服务读出的遮罩描述。
  final String? barrierLabel;

  /// 是否避开系统状态栏、刘海和底部手势区。
  final bool useSafeArea;

  /// 路由名称与参数。
  final RouteSettings? routeSettings;

  /// 锚点。
  final Offset? anchorPoint;

  /// 焦点遍历策略。
  final TraversalEdgeBehavior? traversalEdgeBehavior;

  /// 打开后是否主动请求焦点。
  final bool? requestFocus;

  /// 动画样式配置。
  final AnimationStyle? animationStyle;

  /// 弹窗卡片背景色；null 时使用主题 `surface`。
  final Color? backgroundColor;

  /// 卡片圆角半径，默认 20.0。
  final double borderRadius;

  /// 卡片最大宽度，默认 420.0。
  final double maxWidth;

  /// 卡片最小宽度，默认 280.0。
  final double minWidth;

  /// 弹层阴影高度，默认 6.0。
  final double elevation;

  /// 屏幕四周内边距，默认 24.0。
  final EdgeInsets insetPadding;

  /// 弹窗在屏幕中的对齐位置，默认居中 [Alignment.center]。
  final Alignment alignment;

  /// 内容裁切策略，默认 [Clip.antiAlias]。
  final Clip clipBehavior;

  /// 遮罩背景毛玻璃模糊度（sigmaX/Y），默认 0.0（不模糊）。建议设置 4.0 ~ 8.0 获取高质感磨砂背景。
  final double backdropBlur;

  /// 弹窗进场动画类型。
  final ModalTransitionType transitionType;

  /// 自定义进场动画时长。
  final Duration? transitionDuration;

  /// 自动关闭延迟；用于限时确认或自动消失通知。
  final Duration? autoCloseDuration;

  /// 打开弹窗时是否触发触觉振动。
  final bool vibrate;

  /// 打开弹窗时是否发出系统提示音。
  final bool playSound;
}

// ── 基础与通用 API ─────────────────────────────────────────────────────────────

/// 展示自定义 Builder 的底层 Modal 对话框。
Future<T?> showModal<T>({
  BuildContext? context,
  required WidgetBuilder builder,
  AppModalOptions options = const AppModalOptions(),
}) {
  final targetContext = context ?? rootNavigatorKey.currentContext;
  if (targetContext == null) return Future.value(null);

  if (options.vibrate) HapticFeedback.mediumImpact();
  if (options.playSound) SystemSound.play(SystemSoundType.click);

  if (options.transitionType == ModalTransitionType.material3 && options.backdropBlur <= 0) {
    return showDialog<T>(
      context: targetContext,
      builder: (modalCtx) => Center(
        child: _AutoCloseWrapper<T>(
          duration: options.autoCloseDuration,
          child: builder(modalCtx),
        ),
      ),
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
  }

  // 自定义过渡动画 / 毛玻璃支持
  return showGeneralDialog<T>(
    context: targetContext,
    barrierDismissible: options.barrierDismissible,
    barrierColor: options.barrierColor ?? Colors.black.withValues(alpha: 0.54),
    barrierLabel: options.barrierLabel ?? 'Dismiss',
    useRootNavigator: options.useRootNavigator,
    routeSettings: options.routeSettings,
    anchorPoint: options.anchorPoint,
    transitionDuration: options.transitionDuration ?? const Duration(milliseconds: 220),
    pageBuilder: (ctx, anim1, anim2) {
      Widget content = builder(ctx);
      if (options.useSafeArea) content = SafeArea(child: content);
      return Center(
        child: _AutoCloseWrapper<T>(
          duration: options.autoCloseDuration,
          child: content,
        ),
      );
    },
    transitionBuilder: (ctx, anim, secondaryAnim, child) {
      final curveAnim = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      Widget animatedChild;
      switch (options.transitionType) {
        case ModalTransitionType.scale:
          animatedChild = ScaleTransition(
            scale: Tween<double>(begin: 0.85, end: 1.0).animate(curveAnim),
            child: FadeTransition(opacity: curveAnim, child: child),
          );
          break;
        case ModalTransitionType.fade:
          animatedChild = FadeTransition(opacity: curveAnim, child: child);
          break;
        case ModalTransitionType.slideFromBottom:
          animatedChild = SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(curveAnim),
            child: FadeTransition(opacity: curveAnim, child: child),
          );
          break;
        case ModalTransitionType.slideFromTop:
          animatedChild = SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, -0.15), end: Offset.zero).animate(curveAnim),
            child: FadeTransition(opacity: curveAnim, child: child),
          );
          break;
        case ModalTransitionType.material3:
          animatedChild = FadeTransition(
            opacity: curveAnim,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.9, end: 1.0).animate(curveAnim),
              child: child,
            ),
          );
          break;
      }

      if (options.backdropBlur > 0) {
        return BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: options.backdropBlur * anim.value,
            sigmaY: options.backdropBlur * anim.value,
          ),
          child: animatedChild,
        );
      }
      return animatedChild;
    },
  );
}

/// 全功能综合 Modal 对话框。
Future<ModalResult<T>> showModalDialog<T>({
  BuildContext? context,
  // 标题
  String? title,
  Widget? titleWidget,
  TextStyle? titleStyle,
  TextAlign titleAlign = TextAlign.start,
  // 内容
  String? content,
  Widget? contentWidget,
  TextStyle? contentStyle,
  TextAlign contentAlign = TextAlign.start,
  InlineSpan? richContent,
  double? contentMaxHeight,
  // 顶部图标与右上角关闭
  Widget? icon,
  bool showCloseButton = false,
  VoidCallback? onClose,
  // 输入框相关 (Prompt 模式)
  bool editable = false,
  String? placeholderText,
  String? initialValue,
  int? maxLength,
  int maxLines = 1,
  int? minLines,
  bool obscureText = false,
  TextInputType keyboardType = TextInputType.text,
  List<TextInputFormatter>? inputFormatters,
  Widget? inputPrefixIcon,
  Widget? inputSuffixIcon,
  bool autofocus = true,
  String? Function(String?)? validator,
  // 底部勾选框 (如“不再提醒”)
  String? checkboxText,
  bool initialCheckboxValue = false,
  ValueChanged<bool>? onCheckboxChanged,
  // 按钮相关
  bool showCancel = true,
  String cancelText = '取消',
  Color? cancelColor,
  Widget? cancelIcon,
  ButtonStyle? cancelButtonStyle,
  VoidCallback? onCancel,
  bool showConfirm = true,
  String confirmText = '确定',
  Color? confirmColor,
  Widget? confirmIcon,
  ButtonStyle? confirmButtonStyle,
  bool confirmDisabled = false,
  bool isDestructive = false,
  // 第三按钮 (Neutral / 稍后提醒)
  String? neutralText,
  Color? neutralColor,
  Widget? neutralIcon,
  ButtonStyle? neutralButtonStyle,
  FutureOr<bool?> Function()? onNeutral,
  // 布局与回调
  ModalActionsLayout actionsLayout = ModalActionsLayout.auto,
  List<Widget>? customActions,
  FutureOr<bool?> Function(String inputContent)? onConfirm,
  AppModalOptions options = const AppModalOptions(),
}) async {
  final result = await showModal<ModalResult<T>>(
    context: context,
    options: options,
    builder: (modalContext) => _AppModalDialog<T>(
      title: title,
      titleWidget: titleWidget,
      titleStyle: titleStyle,
      titleAlign: titleAlign,
      content: content,
      contentWidget: contentWidget,
      contentStyle: contentStyle,
      contentAlign: contentAlign,
      richContent: richContent,
      contentMaxHeight: contentMaxHeight,
      icon: icon,
      showCloseButton: showCloseButton,
      onClose: onClose,
      editable: editable,
      placeholderText: placeholderText,
      initialValue: initialValue,
      maxLength: maxLength,
      maxLines: maxLines,
      minLines: minLines,
      obscureText: obscureText,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      inputPrefixIcon: inputPrefixIcon,
      inputSuffixIcon: inputSuffixIcon,
      autofocus: autofocus,
      validator: validator,
      checkboxText: checkboxText,
      initialCheckboxValue: initialCheckboxValue,
      onCheckboxChanged: onCheckboxChanged,
      showCancel: showCancel,
      cancelText: cancelText,
      cancelColor: cancelColor,
      cancelIcon: cancelIcon,
      cancelButtonStyle: cancelButtonStyle,
      onCancel: onCancel,
      showConfirm: showConfirm,
      confirmText: confirmText,
      confirmColor: confirmColor,
      confirmIcon: confirmIcon,
      confirmButtonStyle: confirmButtonStyle,
      confirmDisabled: confirmDisabled,
      isDestructive: isDestructive,
      neutralText: neutralText,
      neutralColor: neutralColor,
      neutralIcon: neutralIcon,
      neutralButtonStyle: neutralButtonStyle,
      onNeutral: onNeutral,
      actionsLayout: actionsLayout,
      customActions: customActions,
      onConfirm: onConfirm,
      options: options,
    ),
  );

  return result ?? const ModalResult(cancelled: true);
}

// ── 便捷函数与语义弹窗 ──────────────────────────────────────────────────────────

/// 确认弹层：包含「取消」与「确定」按钮，返回布尔值。
Future<bool> showConfirmModal({
  BuildContext? context,
  required String title,
  String? message,
  Widget? customContent,
  Widget? icon,
  String confirmText = '确认',
  Color? confirmColor,
  Widget? confirmIcon,
  String cancelText = '取消',
  Color? cancelColor,
  String? neutralText,
  bool isDestructive = false,
  String? checkboxText,
  bool initialCheckboxValue = false,
  bool showCloseButton = false,
  FutureOr<bool?> Function()? onConfirm,
  FutureOr<bool?> Function()? onNeutral,
  VoidCallback? onCancel,
  AppModalOptions options = const AppModalOptions(),
}) async {
  final result = await showModalDialog<void>(
    context: context,
    title: title,
    content: message,
    contentWidget: customContent,
    icon: icon,
    showCancel: true,
    cancelText: cancelText,
    cancelColor: cancelColor,
    confirmText: confirmText,
    confirmColor: confirmColor,
    confirmIcon: confirmIcon,
    neutralText: neutralText,
    onNeutral: onNeutral,
    isDestructive: isDestructive,
    checkboxText: checkboxText,
    initialCheckboxValue: initialCheckboxValue,
    showCloseButton: showCloseButton,
    onConfirm: onConfirm != null ? (_) => onConfirm() : null,
    onCancel: onCancel,
    options: options,
  );
  return result.isConfirmed;
}

/// 提示告警弹层：仅包含一个确认按钮。
Future<void> showAlertModal({
  BuildContext? context,
  required String title,
  String? message,
  Widget? customContent,
  Widget? icon,
  String buttonText = '知道了',
  Color? buttonColor,
  bool showCloseButton = false,
  VoidCallback? onConfirm,
  AppModalOptions options = const AppModalOptions(),
}) async {
  await showModalDialog<void>(
    context: context,
    title: title,
    content: message,
    contentWidget: customContent,
    icon: icon,
    showCancel: false,
    confirmText: buttonText,
    confirmColor: buttonColor,
    showCloseButton: showCloseButton,
    onConfirm: onConfirm != null
        ? (_) {
            onConfirm();
            return true;
          }
        : null,
    options: options,
  );
}

/// 成功提示弹窗（带绿色成功图标与音效反馈）。
Future<void> showSuccessModal({
  BuildContext? context,
  required String title,
  String? message,
  String buttonText = '完成',
  Duration? autoCloseDuration,
  AppModalOptions options = const AppModalOptions(vibrate: true, playSound: true),
}) async {
  await showModalDialog<void>(
    context: context,
    icon: const Icon(Icons.check_circle_outline, size: 56, color: Colors.green),
    title: title,
    titleAlign: TextAlign.center,
    content: message,
    contentAlign: TextAlign.center,
    showCancel: false,
    confirmText: buttonText,
    confirmColor: Colors.green,
    options: AppModalOptions(
      barrierDismissible: options.barrierDismissible,
      backdropBlur: options.backdropBlur,
      transitionType: options.transitionType,
      autoCloseDuration: autoCloseDuration ?? options.autoCloseDuration,
      vibrate: options.vibrate,
      playSound: options.playSound,
    ),
  );
}

/// 错误提示弹窗（带红色警告图标与错误强调）。
Future<void> showErrorModal({
  BuildContext? context,
  required String title,
  String? message,
  String buttonText = '我知道了',
  AppModalOptions options = const AppModalOptions(vibrate: true),
}) async {
  await showModalDialog<void>(
    context: context,
    icon: const Icon(Icons.error_outline, size: 56, color: Colors.red),
    title: title,
    titleAlign: TextAlign.center,
    content: message,
    contentAlign: TextAlign.center,
    showCancel: false,
    confirmText: buttonText,
    confirmColor: Colors.red,
    options: options,
  );
}

/// 快速输入弹窗（Prompt）：包含单行/多行输入框，返回输入的文本；取消或关闭返回 `null`。
Future<String?> showPromptModal({
  BuildContext? context,
  required String title,
  String? message,
  String? placeholderText,
  String? initialValue,
  int? maxLength,
  int maxLines = 1,
  int? minLines,
  bool obscureText = false,
  TextInputType keyboardType = TextInputType.text,
  List<TextInputFormatter>? inputFormatters,
  Widget? prefixIcon,
  Widget? suffixIcon,
  String? Function(String?)? validator,
  String confirmText = '确定',
  Color? confirmColor,
  String cancelText = '取消',
  bool showCloseButton = false,
  FutureOr<bool?> Function(String inputContent)? onConfirm,
  AppModalOptions options = const AppModalOptions(barrierDismissible: false),
}) async {
  final result = await showModalDialog<void>(
    context: context,
    title: title,
    content: message,
    editable: true,
    placeholderText: placeholderText,
    initialValue: initialValue,
    maxLength: maxLength,
    maxLines: maxLines,
    minLines: minLines,
    obscureText: obscureText,
    keyboardType: keyboardType,
    inputFormatters: inputFormatters,
    inputPrefixIcon: prefixIcon,
    inputSuffixIcon: suffixIcon,
    validator: validator,
    confirmText: confirmText,
    confirmColor: confirmColor,
    cancelText: cancelText,
    showCloseButton: showCloseButton,
    onConfirm: onConfirm,
    options: options,
  );
  return result.isConfirmed ? (result.content ?? '') : null;
}

/// 单选列表选择弹窗。
Future<T?> showRadioListModal<T>({
  BuildContext? context,
  required String title,
  String? message,
  required List<ModalActionItem<T>> items,
  T? initialValue,
  String confirmText = '确定',
  String cancelText = '取消',
  AppModalOptions options = const AppModalOptions(),
}) async {
  final targetContext = context ?? rootNavigatorKey.currentContext;
  if (targetContext == null) return null;

  T? selectedValue = initialValue;

  final result = await showModal<T>(
    context: targetContext,
    options: options,
    builder: (modalContext) {
      return StatefulBuilder(
        builder: (ctx, setModalState) {
          final theme = Theme.of(ctx);
          final colors = theme.colorScheme;
          final mediaQuery = MediaQuery.maybeOf(ctx);
          final screenWidth = mediaQuery?.size.width ?? 400.0;
          final maxAllowed = (screenWidth - options.insetPadding.horizontal);
          final effectiveMax = maxAllowed > options.minWidth ? maxAllowed : options.minWidth;
          final double targetWidth = options.maxWidth <= effectiveMax ? options.maxWidth : effectiveMax;
          final double dialogWidth = (targetWidth.isFinite && targetWidth > 0) ? targetWidth : 360.0;

          return Dialog(
            backgroundColor: options.backgroundColor ?? colors.surface,
            elevation: options.elevation,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(options.borderRadius),
            ),
            child: SizedBox(
              width: dialogWidth,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (message != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        message,
                        style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Flexible(
                      child: SingleChildScrollView(
                        child: RadioGroup<T>(
                          groupValue: selectedValue,
                          onChanged: (val) {
                            if (val != null) {
                              setModalState(() => selectedValue = val);
                            }
                          },
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: items.map((item) {
                              return RadioListTile<T>(
                                value: item.value as T,
                                title: Text(item.title),
                                subtitle: item.subtitle != null ? Text(item.subtitle!) : null,
                                secondary: item.icon,
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(null),
                          child: Text(cancelText),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: selectedValue != null
                              ? () => Navigator.of(ctx).pop(selectedValue)
                              : null,
                          child: Text(confirmText),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );

  return result;
}

// ── 选项列表弹窗（ActionSheet / Menu Modal） ──────────────────────────────────

Future<T?> showActionSheetModal<T>({
  BuildContext? context,
  String? title,
  String? message,
  required List<ModalActionItem<T>> items,
  String cancelText = '取消',
  bool showCancel = true,
  AppModalOptions options = const AppModalOptions(),
}) async {
  final targetContext = context ?? rootNavigatorKey.currentContext;
  if (targetContext == null) return null;

  return showModal<T>(
    context: targetContext,
    options: options,
    builder: (modalContext) {
      final theme = Theme.of(modalContext);
      final colors = theme.colorScheme;
      final mediaQuery = MediaQuery.maybeOf(modalContext);
      final screenWidth = mediaQuery?.size.width ?? 400.0;
      final maxAllowed = (screenWidth - options.insetPadding.horizontal);
      final effectiveMax = maxAllowed > options.minWidth ? maxAllowed : options.minWidth;
      final double targetWidth = options.maxWidth <= effectiveMax ? options.maxWidth : effectiveMax;
      final double dialogWidth = (targetWidth.isFinite && targetWidth > 0) ? targetWidth : 360.0;

      return Dialog(
        backgroundColor: options.backgroundColor ?? colors.surface,
        elevation: options.elevation,
        clipBehavior: options.clipBehavior,
        insetPadding: options.insetPadding,
        alignment: options.alignment,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(options.borderRadius),
        ),
        child: SizedBox(
          width: dialogWidth,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title != null || message != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        if (title != null)
                          Text(
                            title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        if (message != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            message,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                ],
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: items.map((item) {
                        final textColor = item.isDestructive
                            ? colors.error
                            : (item.enabled ? colors.onSurface : colors.onSurface.withValues(alpha: 0.38));
                        return ListTile(
                          leading: item.icon,
                          enabled: item.enabled,
                          title: Text(
                            item.title,
                            style: TextStyle(
                              color: textColor,
                              fontWeight: item.isDestructive ? FontWeight.w600 : FontWeight.w500,
                            ),
                          ),
                          subtitle: item.subtitle != null
                              ? Text(item.subtitle!)
                              : null,
                          onTap: () {
                            Navigator.of(modalContext).pop(item.value);
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ),
                if (showCancel) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: TextButton(
                      onPressed: () => Navigator.of(modalContext).pop(null),
                      child: Text(cancelText),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

// ── 内部统一 Dialog 实现 ────────────────────────────────────────────────────────

class _AutoCloseWrapper<T> extends StatefulWidget {
  const _AutoCloseWrapper({required this.duration, required this.child});
  final Duration? duration;
  final Widget child;

  @override
  State<_AutoCloseWrapper<T>> createState() => _AutoCloseWrapperState<T>();
}

class _AutoCloseWrapperState<T> extends State<_AutoCloseWrapper<T>> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.duration != null && widget.duration! > Duration.zero) {
      _timer = Timer(widget.duration!, () {
        if (mounted) {
          Navigator.of(context).maybePop();
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _AppModalDialog<T> extends StatefulWidget {
  const _AppModalDialog({
    this.title,
    this.titleWidget,
    this.titleStyle,
    this.titleAlign = TextAlign.start,
    this.content,
    this.contentWidget,
    this.contentStyle,
    this.contentAlign = TextAlign.start,
    this.richContent,
    this.contentMaxHeight,
    this.icon,
    this.showCloseButton = false,
    this.onClose,
    this.editable = false,
    this.placeholderText,
    this.initialValue,
    this.maxLength,
    this.maxLines = 1,
    this.minLines,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.inputFormatters,
    this.inputPrefixIcon,
    this.inputSuffixIcon,
    this.autofocus = true,
    this.validator,
    this.checkboxText,
    this.initialCheckboxValue = false,
    this.onCheckboxChanged,
    this.showCancel = true,
    required this.cancelText,
    this.cancelColor,
    this.cancelIcon,
    this.cancelButtonStyle,
    this.onCancel,
    this.showConfirm = true,
    required this.confirmText,
    this.confirmColor,
    this.confirmIcon,
    this.confirmButtonStyle,
    this.confirmDisabled = false,
    this.isDestructive = false,
    this.neutralText,
    this.neutralColor,
    this.neutralIcon,
    this.neutralButtonStyle,
    this.onNeutral,
    this.actionsLayout = ModalActionsLayout.auto,
    this.customActions,
    this.onConfirm,
    required this.options,
  });

  final String? title;
  final Widget? titleWidget;
  final TextStyle? titleStyle;
  final TextAlign titleAlign;

  final String? content;
  final Widget? contentWidget;
  final TextStyle? contentStyle;
  final TextAlign contentAlign;
  final InlineSpan? richContent;
  final double? contentMaxHeight;

  final Widget? icon;
  final bool showCloseButton;
  final VoidCallback? onClose;

  final bool editable;
  final String? placeholderText;
  final String? initialValue;
  final int? maxLength;
  final int maxLines;
  final int? minLines;
  final bool obscureText;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final Widget? inputPrefixIcon;
  final Widget? inputSuffixIcon;
  final bool autofocus;
  final String? Function(String?)? validator;

  final String? checkboxText;
  final bool initialCheckboxValue;
  final ValueChanged<bool>? onCheckboxChanged;

  final bool showCancel;
  final String cancelText;
  final Color? cancelColor;
  final Widget? cancelIcon;
  final ButtonStyle? cancelButtonStyle;
  final VoidCallback? onCancel;

  final bool showConfirm;
  final String confirmText;
  final Color? confirmColor;
  final Widget? confirmIcon;
  final ButtonStyle? confirmButtonStyle;
  final bool confirmDisabled;
  final bool isDestructive;

  final String? neutralText;
  final Color? neutralColor;
  final Widget? neutralIcon;
  final ButtonStyle? neutralButtonStyle;
  final FutureOr<bool?> Function()? onNeutral;

  final ModalActionsLayout actionsLayout;
  final List<Widget>? customActions;
  final FutureOr<bool?> Function(String inputContent)? onConfirm;
  final AppModalOptions options;

  @override
  State<_AppModalDialog<T>> createState() => _AppModalDialogState<T>();
}

class _AppModalDialogState<T> extends State<_AppModalDialog<T>> {
  late final TextEditingController _textCtrl;
  final _formKey = GlobalKey<FormState>();
  String? _errorMessage;
  bool _isLoading = false;
  late bool _checkboxChecked;

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController(text: widget.initialValue ?? '');
    _checkboxChecked = widget.initialCheckboxValue;
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleConfirm() async {
    if (widget.confirmDisabled) return;
    final text = _textCtrl.text.trim();
    if (widget.editable && widget.validator != null) {
      final err = widget.validator!(text);
      if (err != null) {
        setState(() => _errorMessage = err);
        return;
      }
    }

    if (widget.onConfirm != null) {
      setState(() => _isLoading = true);
      try {
        final shouldClose = await widget.onConfirm!(text);
        if (!mounted) return;
        if (shouldClose == false) {
          setState(() => _isLoading = false);
          return;
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
        return;
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop(
      ModalResult<T>(
        confirmed: true,
        content: widget.editable ? text : null,
        checkboxValue: widget.checkboxText != null ? _checkboxChecked : null,
      ),
    );
  }

  void _handleCancel() {
    widget.onCancel?.call();
    Navigator.of(context).pop(
      ModalResult<T>(
        cancelled: true,
        checkboxValue: widget.checkboxText != null ? _checkboxChecked : null,
      ),
    );
  }

  void _handleClose() {
    widget.onClose?.call();
    _handleCancel();
  }

  Future<void> _handleNeutral() async {
    if (widget.onNeutral != null) {
      setState(() => _isLoading = true);
      try {
        final shouldClose = await widget.onNeutral!();
        if (!mounted) return;
        if (shouldClose == false) {
          setState(() => _isLoading = false);
          return;
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
        return;
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop(
      ModalResult<T>(
        isNeutral: true,
        checkboxValue: widget.checkboxText != null ? _checkboxChecked : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final options = widget.options;

    final mediaQuery = MediaQuery.maybeOf(context);
    final screenWidth = mediaQuery?.size.width ?? 400.0;
    final maxAllowed = (screenWidth - options.insetPadding.horizontal);
    final effectiveMax = maxAllowed > options.minWidth ? maxAllowed : options.minWidth;
    final double targetWidth = options.maxWidth <= effectiveMax ? options.maxWidth : effectiveMax;
    final double dialogWidth = (targetWidth.isFinite && targetWidth > 0) ? targetWidth : 360.0;

    return Dialog(
      backgroundColor: options.backgroundColor ?? colors.surface,
      elevation: options.elevation,
      clipBehavior: options.clipBehavior,
      insetPadding: options.insetPadding,
      alignment: options.alignment,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(options.borderRadius),
      ),
      child: SizedBox(
        width: dialogWidth,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. 图标
                  if (widget.icon != null) ...[
                    Center(child: widget.icon),
                    const SizedBox(height: 16),
                  ],

                  // 2. 标题
                  if (widget.titleWidget != null)
                    widget.titleWidget!
                  else if (widget.title != null)
                    Text(
                      widget.title!,
                      style: widget.titleStyle ??
                          theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      textAlign: widget.icon != null && widget.titleAlign == TextAlign.start
                          ? TextAlign.center
                          : widget.titleAlign,
                    ),

                  // 3. 内容与描述
                  if (widget.contentWidget != null) ...[
                    const SizedBox(height: 12),
                    _buildScrollableContent(widget.contentWidget!),
                  ] else if (widget.richContent != null) ...[
                    const SizedBox(height: 12),
                    _buildScrollableContent(
                      Text.rich(
                        widget.richContent!,
                        style: widget.contentStyle ??
                            theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                              height: 1.45,
                            ),
                        textAlign: widget.contentAlign,
                      ),
                    ),
                  ] else if (widget.content != null) ...[
                    const SizedBox(height: 12),
                    _buildScrollableContent(
                      Text(
                        widget.content!,
                        style: widget.contentStyle ??
                            theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                              height: 1.45,
                            ),
                        textAlign: widget.icon != null && widget.contentAlign == TextAlign.start
                            ? TextAlign.center
                            : widget.contentAlign,
                      ),
                    ),
                  ],

                  // 4. 输入框（Prompt 模式）
                  if (widget.editable) ...[
                    const SizedBox(height: 16),
                    Form(
                      key: _formKey,
                      child: TextField(
                        controller: _textCtrl,
                        maxLength: widget.maxLength,
                        maxLines: widget.maxLines,
                        minLines: widget.minLines,
                        obscureText: widget.obscureText,
                        keyboardType: widget.keyboardType,
                        inputFormatters: widget.inputFormatters,
                        autofocus: widget.autofocus,
                        decoration: InputDecoration(
                          hintText: widget.placeholderText,
                          prefixIcon: widget.inputPrefixIcon,
                          suffixIcon: widget.inputSuffixIcon,
                          errorText: _errorMessage,
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                        onChanged: (_) {
                          if (_errorMessage != null) {
                            setState(() => _errorMessage = null);
                          }
                        },
                        onSubmitted: (_) => _handleConfirm(),
                      ),
                    ),
                  ],

                  // 5. 勾选框（如“不再提醒”）
                  if (widget.checkboxText != null) ...[
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: () {
                        setState(() => _checkboxChecked = !_checkboxChecked);
                        widget.onCheckboxChanged?.call(_checkboxChecked);
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: Checkbox(
                                value: _checkboxChecked,
                                onChanged: (v) {
                                  setState(() => _checkboxChecked = v ?? false);
                                  widget.onCheckboxChanged?.call(_checkboxChecked);
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.checkboxText!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  if (_errorMessage != null && !widget.editable) ...[
                    const SizedBox(height: 10),
                    Text(
                      _errorMessage!,
                      style: TextStyle(color: colors.error, fontSize: 13),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // 6. 按钮组
                  if (widget.customActions != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: widget.customActions!,
                    )
                  else
                    _buildActionButtons(context, colors),
                ],
              ),
            ),

            // 右上角关闭按钮
            if (widget.showCloseButton)
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: _isLoading ? null : _handleClose,
                  tooltip: '关闭',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildScrollableContent(Widget child) {
    if (widget.contentMaxHeight != null) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.contentMaxHeight!),
        child: SingleChildScrollView(child: child),
      );
    }
    return child;
  }

  Widget _buildActionButtons(BuildContext context, ColorScheme colors) {
    final hasNeutral = widget.neutralText != null;
    final bool useVertical = widget.actionsLayout == ModalActionsLayout.vertical ||
        hasNeutral ||
        (widget.actionsLayout == ModalActionsLayout.auto &&
            (widget.cancelText.length > 5 || widget.confirmText.length > 5));

    final cancelButton = widget.showCancel
        ? TextButton(
            onPressed: _isLoading ? null : _handleCancel,
            style: widget.cancelButtonStyle ??
                (widget.cancelColor != null
                    ? TextButton.styleFrom(foregroundColor: widget.cancelColor)
                    : null),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.cancelIcon != null) ...[
                  widget.cancelIcon!,
                  const SizedBox(width: 6),
                ],
                Text(widget.cancelText),
              ],
            ),
          )
        : null;

    final neutralButton = hasNeutral
        ? TextButton(
            onPressed: _isLoading ? null : _handleNeutral,
            style: widget.neutralButtonStyle ??
                (widget.neutralColor != null
                    ? TextButton.styleFrom(foregroundColor: widget.neutralColor)
                    : null),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.neutralIcon != null) ...[
                  widget.neutralIcon!,
                  const SizedBox(width: 6),
                ],
                Text(widget.neutralText!),
              ],
            ),
          )
        : null;

    final confirmButton = widget.showConfirm
        ? FilledButton(
            style: widget.confirmButtonStyle ??
                (widget.isDestructive
                    ? FilledButton.styleFrom(
                        backgroundColor: colors.error,
                        foregroundColor: colors.onError,
                      )
                    : (widget.confirmColor != null
                        ? FilledButton.styleFrom(
                            backgroundColor: widget.confirmColor,
                          )
                        : null)),
            onPressed: (_isLoading || widget.confirmDisabled) ? null : _handleConfirm,
            child: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.confirmIcon != null) ...[
                        widget.confirmIcon!,
                        const SizedBox(width: 6),
                      ],
                      Text(widget.confirmText),
                    ],
                  ),
          )
        : null;

    // 单按钮模式
    if (cancelButton == null && neutralButton == null) {
      return Align(
        alignment: Alignment.centerRight,
        child: confirmButton ?? const SizedBox.shrink(),
      );
    }

    if (useVertical) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (confirmButton != null) confirmButton,
          if (neutralButton != null) ...[
            const SizedBox(height: 8),
            neutralButton,
          ],
          if (cancelButton != null) ...[
            const SizedBox(height: 8),
            cancelButton,
          ],
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (cancelButton != null) cancelButton,
        if (neutralButton != null) ...[
          const SizedBox(width: 8),
          neutralButton,
        ],
        if (confirmButton != null) ...[
          const SizedBox(width: 12),
          confirmButton,
        ],
      ],
    );
  }
}
