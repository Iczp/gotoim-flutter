import 'package:flutter/material.dart';

import 'adaptive_page_presentation.dart';

/// 键盘出现时半屏页的处理方式。
enum AdaptiveKeyboardBehavior {
  /// 整体上移避开键盘，保证底部操作区可见
  resize,

  /// 不额外处理键盘 Insets，内容可能被键盘覆盖（适合纯展示页）
  overlay,
}

/// 自定义 Header 构建器签名。
/// controller 实际类型为 [AdaptivePageController]，使用 dynamic 以避免
/// config 与 controller 之间的循环 import。
typedef AdaptiveHeaderBuilder = Widget Function(
    BuildContext context, dynamic controller);

@immutable
class AdaptivePageConfig {
  const AdaptivePageConfig({
    required this.title,
    this.canConvertToPage = true,
    this.sheetSizingMode = AdaptiveSheetSizingMode.content,
    this.maxContentHeightFactor = .75,
    this.initialChildSize = .60,
    this.minChildSize = .40,
    this.maxChildSize = .95,
    this.useRootNavigator = true,
    this.fullPageMinWidth,
    // ── 外观 ──
    this.backgroundColor,
    this.barrierColor,
    this.elevation,
    this.shape,
    this.sheetBorderRadius = 24,
    this.clipBehavior = Clip.antiAlias,
    this.maxWidth,
    this.constraints,
    // ── 交互与适配 ──
    this.isDismissible = true,
    this.enableDrag = true,
    this.useSafeArea = false,
    this.keyboardBehavior = AdaptiveKeyboardBehavior.resize,
    this.animationStyle,
    this.routeSettings,
    // ── Header ──
    this.showDragHandle = true,
    this.dragHandleColor,
    this.dragHandleSize,
    this.showCloseButton = true,
    this.showConvertButton,
    this.leadingAction,
    this.trailingActions = const [],
    this.headerBuilder,
  })  : assert(
          maxContentHeightFactor == null ||
              (maxContentHeightFactor > 0 && maxContentHeightFactor <= 1),
          'maxContentHeightFactor must be in (0, 1] or null for wrap-content.',
        ),
        assert(initialChildSize > 0 && initialChildSize <= 1),
        assert(minChildSize > 0 && minChildSize <= initialChildSize),
        assert(maxChildSize >= initialChildSize && maxChildSize <= 1),
        assert(sheetBorderRadius >= 0);

  // ── 基本 ──

  /// Sheet / 全页的标题文字。
  final String title;

  /// 是否允许从半屏切换到完整页路由。
  final bool canConvertToPage;

  /// Sheet 高度控制模式。
  final AdaptiveSheetSizingMode sheetSizingMode;

  /// [AdaptiveSheetSizingMode.content] 模式下 Sheet 最大高度占比。
  /// 传 `null` 时由内容自身撑开高度（Wrap Content，适合短列表/操作菜单）。
  final double? maxContentHeightFactor;

  /// [AdaptiveSheetSizingMode.draggable] 模式下初始高度占比。
  final double initialChildSize;

  /// [AdaptiveSheetSizingMode.draggable] 模式下最小高度占比。
  final double minChildSize;

  /// [AdaptiveSheetSizingMode.draggable] 模式下最大高度占比。
  final double maxChildSize;

  /// 是否在根 Navigator 上展示。
  final bool useRootNavigator;

  /// 屏幕宽度 ≥ 此值时，[AdaptivePage.open] 直接以全页路由打开；
  /// 小于此值时以 Sheet 打开，可手动转换为全页。
  final double? fullPageMinWidth;

  // ── 外观 ──

  /// Sheet 及全页的背景色；null 时使用主题 `colorScheme.surface`。
  final Color? backgroundColor;

  /// Sheet 遮罩颜色；null 时使用 Material 默认（半透明黑）。
  final Color? barrierColor;

  /// 弹层阴影高度；null 时使用 Material 默认值。
  final double? elevation;

  /// 自定义弹层外形；如果为 null 则使用 [sheetBorderRadius] 生成顶部圆角。
  final ShapeBorder? shape;

  /// Sheet 顶部圆角半径，默认 24（仅在 [shape] 为 null 时生效）。
  final double sheetBorderRadius;

  /// 内容裁切策略，默认 [Clip.antiAlias]。
  final Clip clipBehavior;

  /// Sheet 最大宽度限制（桌面宽屏防止弹层过宽，如 560）。
  final double? maxWidth;

  /// 弹层的额外尺寸约束（优先级高于 [maxWidth]）。
  final BoxConstraints? constraints;

  // ── 交互与适配 ──

  /// 点击遮罩是否关闭 Sheet；默认 true。
  final bool isDismissible;

  /// 非 draggable 模式下是否允许向下拖拽关闭；默认 true。
  final bool enableDrag;

  /// 是否避开状态栏、刘海和底部手势区；默认 false（由内部 Material/Header 处理）。
  final bool useSafeArea;

  /// 键盘出现时的布局处理策略，默认 [AdaptiveKeyboardBehavior.resize]。
  final AdaptiveKeyboardBehavior keyboardBehavior;

  /// Sheet 打开 / 关闭动画配置；null 使用 Material 默认动画。
  final AnimationStyle? animationStyle;

  /// 路由标识，用于埋点与测试定位。
  final RouteSettings? routeSettings;

  // ── Header ──

  /// 是否显示 Header 顶部拖拽指示条；默认 true。
  final bool showDragHandle;

  /// 顶部拖拽指示条颜色；未设置时使用主题默认颜色。
  final Color? dragHandleColor;

  /// 顶部拖拽指示条尺寸；未设置时使用默认尺寸 (36x4)。
  final Size? dragHandleSize;

  /// 是否显示 Header 右侧关闭按钮；默认 true。
  final bool showCloseButton;

  /// 是否显示 Header 右侧「展开为全页」按钮。
  /// null 时等同于 [canConvertToPage]。
  final bool? showConvertButton;

  /// Header 左侧自定义 Widget（如返回按钮、自定义图标）。
  /// 非 null 时替换默认的空白占位区域。
  final Widget? leadingAction;

  /// Header 右侧额外按钮列表，追加在关闭按钮之前。
  final List<Widget> trailingActions;

  /// 完全自定义 Header 构建器。非 null 时整个内建 Header 均由此提供，
  /// [showDragHandle]、[showCloseButton] 等 Header 参数均不生效。
  final AdaptiveHeaderBuilder? headerBuilder;
}
