import 'package:flutter/material.dart';

import '../ui/adaptive_page.dart';

/// 键盘出现时半屏页的处理方式。
///
/// [resize] 会把半屏页整体上移，适合搜索、输入、选择成员等需要保证
/// 底部操作区始终可见的页面；[overlay] 不额外处理键盘 Insets，适合纯展示页。
enum HalfPageSheetKeyboardBehavior { resize, overlay }

/// 半屏页的展示参数。
///
/// 这个对象只描述「容器行为」，业务内容始终通过 [showHalfPageSheet] 的
/// `builder` 提供。页面不应在此处直接访问 Repository、Dio 或数据库。
@immutable
class HalfPageSheetOptions {
  /// Creates the configuration of a reusable half-page sheet.
  const HalfPageSheetOptions({
    this.heightFactor,
    this.constraints,
    this.useSafeArea = true,
    this.useRootNavigator = false,
    this.isScrollControlled = true,
    this.isDismissible = true,
    this.enableDrag = true,
    this.showDragHandle = true,
    this.dragHandleColor,
    this.dragHandleSize,
    this.backgroundColor,
    this.barrierColor,
    this.elevation,
    this.shape,
    this.clipBehavior = Clip.antiAlias,
    this.keyboardBehavior = HalfPageSheetKeyboardBehavior.resize,
    this.animationStyle,
    this.routeSettings,
  }) : assert(
         heightFactor == null || (heightFactor > 0 && heightFactor <= 1),
         'heightFactor must be in (0, 1].',
       );

  /// 半屏页占可用屏幕高度的比例，范围为 `(0, 1]`。
  ///
  /// 例如 `.55` 适合成员提及，`.62` 适合可分页列表。传 `null` 时由内容
  /// 自己决定高度，适合消息操作菜单等短内容。
  final double? heightFactor;

  /// 路由的额外尺寸限制。桌面端可传 `BoxConstraints(maxWidth: 560)`，避免
  /// 弹层铺满过宽的窗口。
  final BoxConstraints? constraints;

  /// 是否避开状态栏、刘海和底部系统手势区。移动端通常保持 `true`。
  final bool useSafeArea;

  /// 是否在根 Navigator 上展示。存在嵌套 Navigator（如 Tab 内路由）时，
  /// 设为 `true` 可确保遮罩覆盖整个应用。
  final bool useRootNavigator;

  /// 是否允许半屏页使用完整屏幕高度。设置了 [heightFactor]、包含输入框或
  /// 长列表时应保持 `true`；纯菜单可按需关闭。
  final bool isScrollControlled;

  /// 点击遮罩区域能否关闭。提交、支付、不可中断流程可设为 `false`。
  final bool isDismissible;

  /// 是否允许向下拖拽关闭。若 [isDismissible] 为 `false`，建议也设为 `false`。
  final bool enableDrag;

  /// 是否显示 Material 3 顶部拖拽指示条。
  final bool showDragHandle;

  /// 顶部拖拽指示条颜色；未设置时使用当前主题默认颜色。
  final Color? dragHandleColor;

  /// 顶部拖拽指示条尺寸；未设置时使用 Material 默认尺寸。
  final Size? dragHandleSize;

  /// 弹层背景色；通常不需要设置，使用主题的 surface 色即可。
  final Color? backgroundColor;

  /// 遮罩颜色，可用于弱化或加深背景。未设置时使用 Material 默认值。
  final Color? barrierColor;

  /// 弹层阴影高度。通常使用默认值即可。
  final double? elevation;

  /// 弹层外形；例如设置顶部圆角或桌面端的圆角卡片。
  final ShapeBorder? shape;

  /// 内容裁切策略。默认裁切以保证圆角下的图片、列表不会溢出。
  final Clip clipBehavior;

  /// 键盘出现时的布局策略，默认 [HalfPageSheetKeyboardBehavior.resize]。
  final HalfPageSheetKeyboardBehavior keyboardBehavior;

  /// 打开、关闭动画配置。需要更快的菜单或无动画的测试场景时传入。
  final AnimationStyle? animationStyle;

  /// 路由标识，可用于页面观察、埋点和测试定位。
  final RouteSettings? routeSettings;
}

/// 展示统一的底部半屏页，并返回 [Navigator.pop] 携带的结果。
///
/// 内部委托给 [AdaptivePage.sheet]，共享统一的 Sheet 容器渲染、尺寸约束与
/// 键盘避让逻辑。
///
/// `builder` 获得的是半屏页内部的 context；关闭时应使用该 context 调用
/// `Navigator.pop(sheetContext, result)`。长列表应自行使用 `Expanded`，避免
/// 内容超过 [HalfPageSheetOptions.heightFactor] 后发生 RenderFlex overflow。
///
/// 示例：
/// ```dart
/// final selected = await showHalfPageSheet<String>(
///   context: context,
///   options: const HalfPageSheetOptions(heightFactor: .62),
///   builder: (_) => const MemberPicker(),
/// );
/// ```
Future<T?> showHalfPageSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  HalfPageSheetOptions options = const HalfPageSheetOptions(),
}) {
  return AdaptivePage.sheet<T>(
    context,
    config: AdaptivePageConfig(
      title: '',
      canConvertToPage: false,
      showCloseButton: false,
      showConvertButton: false,
      showDragHandle: options.showDragHandle,
      dragHandleColor: options.dragHandleColor,
      dragHandleSize: options.dragHandleSize,
      maxContentHeightFactor: options.heightFactor,
      sheetSizingMode: AdaptiveSheetSizingMode.content,
      backgroundColor: options.backgroundColor,
      barrierColor: options.barrierColor,
      elevation: options.elevation,
      shape: options.shape,
      clipBehavior: options.clipBehavior,
      constraints: options.constraints,
      isDismissible: options.isDismissible,
      enableDrag: options.enableDrag,
      useSafeArea: options.useSafeArea,
      useRootNavigator: options.useRootNavigator,
      keyboardBehavior:
          options.keyboardBehavior == HalfPageSheetKeyboardBehavior.resize
              ? AdaptiveKeyboardBehavior.resize
              : AdaptiveKeyboardBehavior.overlay,
      animationStyle: options.animationStyle,
      routeSettings: options.routeSettings,
    ),
    builder: (sheetContext, _) => builder(sheetContext),
  );
}
