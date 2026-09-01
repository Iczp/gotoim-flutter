import 'package:flutter/material.dart';

import 'adaptive_page_presentation.dart';

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
    this.sheetBorderRadius = 24,
    this.maxWidth,
    // ── 交互 ──
    this.isDismissible = true,
    this.enableDrag = true,
    this.animationStyle,
    this.routeSettings,
    // ── Header ──
    this.showDragHandle = true,
    this.showCloseButton = true,
    this.showConvertButton,
    this.leadingAction,
    this.trailingActions = const [],
    this.headerBuilder,
  })  : assert(maxContentHeightFactor > 0 && maxContentHeightFactor <= 1),
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
  final double maxContentHeightFactor;

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

  /// Sheet 顶部圆角半径，默认 24。
  final double sheetBorderRadius;

  /// Sheet 最大宽度限制（桌面宽屏防止弹层过宽，如 560）。
  /// null 表示不限制。
  final double? maxWidth;

  // ── 交互 ──

  /// 点击遮罩是否关闭 Sheet；默认 true。
  final bool isDismissible;

  /// 非 draggable 模式下是否允许向下拖拽关闭；默认 true。
  final bool enableDrag;

  /// Sheet 打开 / 关闭动画配置；null 使用 Material 默认动画。
  final AnimationStyle? animationStyle;

  /// 路由标识，用于埋点与测试定位。
  final RouteSettings? routeSettings;

  // ── Header ──

  /// 是否显示 Header 顶部拖拽指示条；默认 true。
  final bool showDragHandle;

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
