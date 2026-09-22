import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_navigation.dart';

/// Toast 语义类型，决定默认图标与颜色。
enum ToastType { success, error, warning, info }

/// Toast 屏幕呈现位置。
enum ToastPosition {
  /// 顶部浮动（状态栏下方）
  top,

  /// 屏幕垂直居中浮动
  center,

  /// 底部浮动（导航条上方）
  bottom,
}

/// AppToast 全局配置。
///
/// 可以在应用初始化或设置页修改全局默认位置、偏移量、透明度、是否振动、是否发声等。
abstract final class AppToastConfig {
  /// 全局默认提示位置，默认 [ToastPosition.top]。
  static ToastPosition defaultPosition = ToastPosition.top;

  /// 全局默认额外偏移量，默认 null。
  static Offset? defaultOffset;

  /// 全局默认背景透明度 (0.0 ~ 1.0)，默认 0.95。
  static double defaultOpacity = 0.75;

  /// 全局默认是否振动反馈，默认 `false`。
  static bool defaultVibrate = false;

  /// 全局默认是否播放系统提示音，默认 `false`。
  static bool defaultPlaySound = false;

  /// 全局默认持续时间，默认 2 秒。
  static Duration defaultDuration = const Duration(seconds: 2);

  /// 提示卡片最大宽度（宽屏/桌面端居中约束），默认 460。
  static double maxWidth = 460.0;

  /// 顶部位置距离状态栏/顶边的基础偏移量，默认 16。
  static double topOffset = 16.0;

  /// 底部位置距离底边的基础偏移量，默认 24。
  static double bottomOffset = 24.0;

  /// 提示卡片圆角半径，默认 12。
  static double borderRadius = 12.0;

  /// 统一修改全局配置。
  static void configure({
    ToastPosition? position,
    Offset? offset,
    double? opacity,
    bool? vibrate,
    bool? playSound,
    Duration? duration,
    double? maxWidth,
    double? topOffset,
    double? bottomOffset,
    double? borderRadius,
  }) {
    if (position != null) defaultPosition = position;
    if (offset != null) defaultOffset = offset;
    if (opacity != null) defaultOpacity = opacity.clamp(0.0, 1.0);
    if (vibrate != null) defaultVibrate = vibrate;
    if (playSound != null) defaultPlaySound = playSound;
    if (duration != null) defaultDuration = duration;
    if (maxWidth != null) AppToastConfig.maxWidth = maxWidth;
    if (topOffset != null) AppToastConfig.topOffset = topOffset;
    if (bottomOffset != null) AppToastConfig.bottomOffset = bottomOffset;
    if (borderRadius != null) AppToastConfig.borderRadius = borderRadius;
  }
}

/// 全局短提示的展示参数。
@immutable
class ToastOptions {
  /// Creates toast options. Defaults are suitable for lightweight feedback.
  const ToastOptions({
    this.type = ToastType.info,
    this.position,
    this.offset,
    this.opacity,
    this.vibrate,
    this.playSound,
    this.duration,
    this.maxLines,
    this.actionLabel,
    this.onAction,
    this.icon,
    this.closePrevious = true,
    this.isLoading = false,
  });

  /// 提示语义。成功、失败、警告和普通信息分别有默认图标与主题颜色。
  final ToastType type;

  /// 提示呈现位置；`null` 时使用全局 [AppToastConfig.defaultPosition]。
  final ToastPosition? position;

  /// 自定义像素偏移量 (dx 水平偏移, dy 垂直偏移)；`null` 时使用全局 [AppToastConfig.defaultOffset]。
  final Offset? offset;

  /// 背景透明度 (0.0 ~ 1.0)；`null` 时使用全局 [AppToastConfig.defaultOpacity]。
  final double? opacity;

  /// 是否产生触觉振动反馈；`null` 时使用全局 [AppToastConfig.defaultVibrate]。
  final bool? vibrate;

  /// 是否发出系统提示音；`null` 时使用全局 [AppToastConfig.defaultPlaySound]。
  final bool? playSound;

  /// 自动消失时间；`null` 时使用全局 [AppToastConfig.defaultDuration]。
  final Duration? duration;

  /// 提示文本最大行数；`null` 时由内容自然换行（支持长多行文本）。
  final int? maxLines;

  /// 可选操作按钮文字，例如「撤销」「重试」。必须与 [onAction] 一起提供。
  final String? actionLabel;

  /// 点击可选操作按钮后的回调。回调中应自行处理异步错误。
  final VoidCallback? onAction;

  /// 覆盖默认图标；传入 `null` 使用由 [type] 决定的图标。
  final IconData? icon;

  /// 显示前是否先移除上一条提示，避免高频事件堆积。
  final bool closePrevious;

  /// 是否为异步加载/转圈状态。为 true 时左侧渲染 CircularProgressIndicator。
  final bool isLoading;
}

// ── 全局 OverlayEntry 状态管理 ──────────────────────────────────────────────

_ToastOverlayHandle? _activeToast;

/// 将其他全局浮层插入到当前 Toast 下方。
///
/// 聊天功能面板等全屏底部浮层是在 Toast 出现后才插入的；若直接插入
/// Overlay 顶层，会遮住位于底部的 Toast。
void insertOverlayBelowActiveToast(OverlayState overlay, OverlayEntry entry) {
  final activeToast = _activeToast?.entry;
  if (activeToast?.mounted ?? false) {
    overlay.insert(entry, below: activeToast);
    return;
  }
  overlay.insert(entry);
}

class _ToastOverlayHandle {
  _ToastOverlayHandle(this.entry, this.dismiss);
  final OverlayEntry entry;
  final VoidCallback dismiss;
}

/// 展示全局短提示，不需要页面 [BuildContext]。
///
/// 采用独立 [OverlayEntry] 渲染，支持安全边界约束、防溢出保护、顶部/居中/底部
/// 任意位置浮动与平滑进出场动画。默认位置在屏幕顶部。
bool showToast(
  String message, {
  ToastPosition? position,
  ToastType? type,
  Duration? duration,
  IconData? icon,
  Offset? offset,
  double? opacity,
  bool? vibrate,
  bool? playSound,
  int? maxLines,
  String? actionLabel,
  VoidCallback? onAction,
  bool closePrevious = true,
  ToastOptions options = const ToastOptions(),
}) {
  final navigatorState = rootNavigatorKey.currentState;
  final overlay = navigatorState?.overlay;
  if (overlay == null || message.trim().isEmpty) {
    return false;
  }

  final effectiveType = type ?? options.type;
  final effectivePosition =
      position ?? options.position ?? AppToastConfig.defaultPosition;
  final effectiveOffset =
      offset ?? options.offset ?? AppToastConfig.defaultOffset;
  final effectiveOpacity =
      opacity ?? options.opacity ?? AppToastConfig.defaultOpacity;
  final effectiveVibrate =
      vibrate ?? options.vibrate ?? AppToastConfig.defaultVibrate;
  final effectivePlaySound =
      playSound ?? options.playSound ?? AppToastConfig.defaultPlaySound;
  final effectiveDuration =
      duration ?? options.duration ?? AppToastConfig.defaultDuration;
  final effectiveMaxLines = maxLines ?? options.maxLines;
  final effectiveActionLabel = actionLabel ?? options.actionLabel;
  final effectiveOnAction = onAction ?? options.onAction;
  final effectiveIcon = icon ?? options.icon;
  final effectiveClosePrevious = closePrevious && options.closePrevious;

  final effectiveOptions = ToastOptions(
    type: effectiveType,
    position: effectivePosition,
    offset: effectiveOffset,
    opacity: effectiveOpacity,
    vibrate: effectiveVibrate,
    playSound: effectivePlaySound,
    duration: effectiveDuration,
    maxLines: effectiveMaxLines,
    actionLabel: effectiveActionLabel,
    onAction: effectiveOnAction,
    icon: effectiveIcon,
    closePrevious: effectiveClosePrevious,
    isLoading: options.isLoading,
  );

  // 1. 触觉振动反馈
  if (effectiveVibrate) {
    switch (effectiveType) {
      case ToastType.error:
        HapticFeedback.heavyImpact();
      case ToastType.warning:
        HapticFeedback.mediumImpact();
      case ToastType.success:
      case ToastType.info:
        HapticFeedback.lightImpact();
    }
  }

  // 2. 声音反馈
  if (effectivePlaySound) {
    switch (effectiveType) {
      case ToastType.error:
      case ToastType.warning:
        SystemSound.play(SystemSoundType.alert);
      case ToastType.success:
      case ToastType.info:
        SystemSound.play(SystemSoundType.click);
    }
  }

  // 3. 关闭前一条 Toast
  if (effectiveClosePrevious && _activeToast != null) {
    _activeToast!.dismiss();
    _activeToast = null;
  }

  late final OverlayEntry entry;
  void removeEntry() {
    if (entry.mounted) {
      entry.remove();
    }
    if (_activeToast?.entry == entry) {
      _activeToast = null;
    }
  }

  entry = OverlayEntry(
    builder:
        (context) => _ToastOverlayHost(
          message: message,
          options: effectiveOptions,
          onDismiss: removeEntry,
        ),
  );

  _activeToast = _ToastOverlayHandle(entry, removeEntry);
  overlay.insert(entry);
  return true;
}

/// 快捷成功提示。
bool showSuccessToast(
  String message, {
  ToastPosition? position,
  Duration? duration,
  IconData? icon,
  Offset? offset,
  double? opacity,
  bool? vibrate,
  bool? playSound,
  int? maxLines,
  String? actionLabel,
  VoidCallback? onAction,
  bool closePrevious = true,
  ToastOptions options = const ToastOptions(),
}) => showToast(
  message,
  type: ToastType.success,
  position: position ?? options.position,
  duration: duration ?? options.duration,
  icon: icon ?? options.icon,
  offset: offset ?? options.offset,
  opacity: opacity ?? options.opacity,
  vibrate: vibrate ?? options.vibrate,
  playSound: playSound ?? options.playSound,
  maxLines: maxLines ?? options.maxLines,
  actionLabel: actionLabel ?? options.actionLabel,
  onAction: onAction ?? options.onAction,
  closePrevious: closePrevious && options.closePrevious,
  options: options,
);

/// 快捷失败提示。
bool showErrorToast(
  String message, {
  ToastPosition? position,
  Duration? duration,
  IconData? icon,
  Offset? offset,
  double? opacity,
  bool? vibrate,
  bool? playSound,
  int? maxLines,
  String? actionLabel,
  VoidCallback? onAction,
  bool closePrevious = true,
  ToastOptions options = const ToastOptions(),
}) => showToast(
  message,
  type: ToastType.error,
  position: position ?? options.position,
  duration: duration ?? options.duration,
  icon: icon ?? options.icon,
  offset: offset ?? options.offset,
  opacity: opacity ?? options.opacity,
  vibrate: vibrate ?? options.vibrate,
  playSound: playSound ?? options.playSound,
  maxLines: maxLines ?? options.maxLines,
  actionLabel: actionLabel ?? options.actionLabel,
  onAction: onAction ?? options.onAction,
  closePrevious: closePrevious && options.closePrevious,
  options: options,
);

/// 快捷警告提示。
bool showWarningToast(
  String message, {
  ToastPosition? position,
  Duration? duration,
  IconData? icon,
  Offset? offset,
  double? opacity,
  bool? vibrate,
  bool? playSound,
  int? maxLines,
  String? actionLabel,
  VoidCallback? onAction,
  bool closePrevious = true,
  ToastOptions options = const ToastOptions(),
}) => showToast(
  message,
  type: ToastType.warning,
  position: position ?? options.position,
  duration: duration ?? options.duration,
  icon: icon ?? options.icon,
  offset: offset ?? options.offset,
  opacity: opacity ?? options.opacity,
  vibrate: vibrate ?? options.vibrate,
  playSound: playSound ?? options.playSound,
  maxLines: maxLines ?? options.maxLines,
  actionLabel: actionLabel ?? options.actionLabel,
  onAction: onAction ?? options.onAction,
  closePrevious: closePrevious && options.closePrevious,
  options: options,
);

/// 快捷普通信息提示。
bool showInfoToast(
  String message, {
  ToastPosition? position,
  Duration? duration,
  IconData? icon,
  Offset? offset,
  double? opacity,
  bool? vibrate,
  bool? playSound,
  int? maxLines,
  String? actionLabel,
  VoidCallback? onAction,
  bool closePrevious = true,
  ToastOptions options = const ToastOptions(),
}) => showToast(
  message,
  type: ToastType.info,
  position: position ?? options.position,
  duration: duration ?? options.duration,
  icon: icon ?? options.icon,
  offset: offset ?? options.offset,
  opacity: opacity ?? options.opacity,
  vibrate: vibrate ?? options.vibrate,
  playSound: playSound ?? options.playSound,
  maxLines: maxLines ?? options.maxLines,
  actionLabel: actionLabel ?? options.actionLabel,
  onAction: onAction ?? options.onAction,
  closePrevious: closePrevious && options.closePrevious,
  options: options,
);

/// 展示全局 Loading 提示，返回一个可主动关闭该 Loading 的回调。
///
/// 采用全局独立 Overlay 渲染，不依赖任何页面 BuildContext。
/// 即使弹窗关闭或页面销毁，也能持续展示并在后台任务完成时自动或手动销毁。
VoidCallback showLoadingToast(
  String message, {
  ToastPosition? position,
  Offset? offset,
  double? opacity,
  int? maxLines,
  Duration? fallbackTimeout,
}) {
  showToast(
    message,
    type: ToastType.info,
    position: position ?? ToastPosition.top,
    offset: offset,
    opacity: opacity,
    maxLines: maxLines,
    duration: fallbackTimeout ?? const Duration(seconds: 60),
    closePrevious: true,
    options: const ToastOptions(type: ToastType.info, isLoading: true),
  );
  return dismissActiveToast;
}

/// 手动关闭当前正在展示的全局 Toast / Loading。
void dismissActiveToast() {
  if (_activeToast != null) {
    _activeToast!.dismiss();
    _activeToast = null;
  }
}

// ── Overlay 宿主组件与动画 ───────────────────────────────────────────────────

class _ToastOverlayHost extends StatefulWidget {
  const _ToastOverlayHost({
    required this.message,
    required this.options,
    required this.onDismiss,
  });

  final String message;
  final ToastOptions options;
  final VoidCallback onDismiss;

  @override
  State<_ToastOverlayHost> createState() => _ToastOverlayHostState();
}

class _ToastOverlayHostState extends State<_ToastOverlayHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    final position = widget.options.position ?? AppToastConfig.defaultPosition;
    final duration = widget.options.duration ?? AppToastConfig.defaultDuration;

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 180),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    final slideBegin = switch (position) {
      ToastPosition.top => const Offset(0, -0.35),
      ToastPosition.center => const Offset(0, -0.1),
      ToastPosition.bottom => const Offset(0, 0.35),
    };

    _slideAnimation = Tween<Offset>(
      begin: slideBegin,
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      ),
    );

    _controller.forward();
    _dismissTimer = Timer(duration, _startDismiss);
  }

  void _startDismiss() {
    if (!mounted) return;
    _controller.reverse().then((_) {
      if (mounted) {
        widget.onDismiss();
      }
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = _ToastStyle.from(widget.options.type, scheme);
    final position = widget.options.position ?? AppToastConfig.defaultPosition;
    final effectiveOpacity = (widget.options.opacity ??
            AppToastConfig.defaultOpacity)
        .clamp(0.0, 1.0);
    final effectiveOffset =
        widget.options.offset ?? AppToastConfig.defaultOffset ?? Offset.zero;

    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.padding.top;
    final bottomPadding = mediaQuery.padding.bottom;
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;

    // ── 关键：安全边界计算，防止偏移量将 Toast 完全移出屏幕 ──
    // 水平方向最大允许偏移，保留至少 60px 可视区域
    final maxSafeDx = (screenWidth / 2 - 40.0).clamp(0.0, double.infinity);
    final clampedDx = effectiveOffset.dx.clamp(-maxSafeDx, maxSafeDx);

    // 垂直方向根据位置计算基准边距与安全限制
    final double safeTop;
    final double safeBottom;
    final Alignment alignment;

    switch (position) {
      case ToastPosition.top:
        alignment = Alignment.topCenter;
        // 顶部限制在 (状态栏 + 4) 到 (屏幕底 - 80) 之间
        final computedTop =
            topPadding + AppToastConfig.topOffset + effectiveOffset.dy;
        safeTop = computedTop.clamp(topPadding + 4.0, screenHeight - 120.0);
        safeBottom = 0.0;
      case ToastPosition.center:
        alignment = Alignment.center;
        // 居中偏移限制在上下可视区内
        final maxCenterDy = (screenHeight / 2 - topPadding - 80.0).clamp(
          0.0,
          double.infinity,
        );
        final clampedCenterDy = effectiveOffset.dy.clamp(
          -maxCenterDy,
          maxCenterDy,
        );
        safeTop = clampedCenterDy > 0 ? clampedCenterDy : 0.0;
        safeBottom = clampedCenterDy < 0 ? -clampedCenterDy : 0.0;
      case ToastPosition.bottom:
        alignment = Alignment.bottomCenter;
        // 底部限制在 (手势条 + 4) 到 (屏幕顶 + 80) 之间
        final computedBottom =
            bottomPadding + AppToastConfig.bottomOffset - effectiveOffset.dy;
        safeBottom = computedBottom.clamp(
          bottomPadding + 4.0,
          screenHeight - 120.0,
        );
        safeTop = 0.0;
    }

    final backgroundColor = style.backgroundColor.withValues(
      alpha: effectiveOpacity,
    );

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: Align(
          alignment: alignment,
          child: Padding(
            padding: EdgeInsets.only(
              top: safeTop,
              bottom: safeBottom,
              left: 16.0,
              right: 16.0,
            ),
            child: Transform.translate(
              offset: Offset(clampedDx, 0),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: AppToastConfig.maxWidth,
                      minHeight: 48,
                    ),
                    child: Material(
                      color: backgroundColor,
                      elevation: 6.0,
                      shadowColor: Colors.black.withValues(alpha: 0.25),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppToastConfig.borderRadius,
                        ),
                      ),
                      child: InkWell(
                        onTap: _startDismiss,
                        borderRadius: BorderRadius.circular(
                          AppToastConfig.borderRadius,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child:
                                    widget.options.isLoading
                                        ? SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  style.foregroundColor,
                                                ),
                                          ),
                                        )
                                        : Icon(
                                          widget.options.icon ?? style.icon,
                                          color: style.foregroundColor,
                                          size: 20,
                                        ),
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  widget.message,
                                  softWrap: true,
                                  maxLines: widget.options.maxLines,
                                  overflow:
                                      widget.options.maxLines != null
                                          ? TextOverflow.ellipsis
                                          : TextOverflow.clip,
                                  style: TextStyle(
                                    color: style.foregroundColor,
                                    fontWeight: FontWeight.w500,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                              if (widget.options.actionLabel != null &&
                                  widget.options.onAction != null) ...[
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () {
                                    widget.options.onAction!();
                                    _startDismiss();
                                  },
                                  child: Text(
                                    widget.options.actionLabel!,
                                    style: TextStyle(
                                      color: style.foregroundColor,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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
