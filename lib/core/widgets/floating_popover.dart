import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../native/native.dart';

/// 浮动菜单定位模式。
enum FloatingPlacement {
  /// 自动探测（气泡菜单首选：优先在气泡上方，空间不足则在下方，横向自动贴靠并钳制在屏幕内）
  auto,

  /// 头像定位（头像菜单专用：横向与头像对齐，纵向与头像顶部对齐，除非在底部则向上对齐，且绝不超屏）
  avatar,

  /// 居中上方
  top,

  /// 居中下方
  bottom,

  /// 目标左侧
  left,

  /// 目标右侧
  right,

  /// 上方左对齐
  topStart,

  /// 上方右对齐
  topEnd,

  /// 下方左对齐
  bottomStart,

  /// 下方右对齐
  bottomEnd,
}

/// 浮层控制器。
class FloatingPopoverController extends ChangeNotifier {
  VoidCallback? _show;
  VoidCallback? _hide;
  bool _visible = false;

  bool get isVisible => _visible;

  void show() => _show?.call();
  void hide() => _hide?.call();
  void toggle() => _visible ? hide() : show();

  void _bind(VoidCallback show, VoidCallback hide) {
    _show = show;
    _hide = hide;
  }

  void _setVisible(bool value) {
    if (_visible == value) return;
    _visible = value;
    notifyListeners();
  }
}

/// 浮层菜单包裹组件（支持边界防溢出与头像/气泡自动对齐）。
class FloatingPopover extends StatefulWidget {
  const FloatingPopover({
    required this.child,
    required this.contentBuilder,
    super.key,
    this.controller,
    this.placement = FloatingPlacement.auto,
    this.offset = const Offset(0, 8),
    this.dismissOnTapOutside = true,
    this.dismissOnEscape = true,
    this.dismissOnScroll = true,
    this.useCard = false,
    this.vibrate = true,
    this.vibrateCount = 1,
    this.vibrateInterval = const Duration(milliseconds: 110),
    this.screenMargin = 8.0,
    this.onLongPress,
    this.onSecondaryTap,
  });

  final Widget child;
  final WidgetBuilder contentBuilder;
  final FloatingPopoverController? controller;
  final FloatingPlacement placement;
  final Offset offset;
  final bool dismissOnTapOutside;
  final bool dismissOnEscape;

  /// 当所属可滚动列表发生滚动时是否自动关闭（默认 true）
  final bool dismissOnScroll;

  final bool useCard;
  final bool vibrate;

  /// 振动反馈次数（默认为 1 次，按住头像等场景可设置为 2 次）
  final int vibrateCount;

  /// 多次振动之间的间隔时间
  final Duration vibrateInterval;

  final double screenMargin;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;

  /// 关闭所有当前处于打开状态的浮层菜单
  static void hideAll() {
    for (final state in _FloatingPopoverState._activePopovers.toList()) {
      state._hide();
    }
  }

  @override
  State<FloatingPopover> createState() => _FloatingPopoverState();
}

class _FloatingPopoverState extends State<FloatingPopover> {
  static final Set<_FloatingPopoverState> _activePopovers = <_FloatingPopoverState>{};
  OverlayEntry? _entry;
  ScrollPosition? _scrollPosition;

  @override
  void initState() {
    super.initState();
    widget.controller?._bind(_show, _hide);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribeScroll();
  }

  void _subscribeScroll() {
    final scrollable = Scrollable.maybeOf(context);
    final position = scrollable?.position;
    if (position != _scrollPosition) {
      _scrollPosition?.removeListener(_onScroll);
      _scrollPosition = position;
      _scrollPosition?.addListener(_onScroll);
    }
  }

  void _onScroll() {
    if (widget.dismissOnScroll && _entry != null) {
      _hide();
    }
  }

  @override
  void didUpdateWidget(FloatingPopover oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.controller?._bind(_show, _hide);
    _subscribeScroll();
  }

  @override
  void dispose() {
    _activePopovers.remove(this);
    _scrollPosition?.removeListener(_onScroll);
    _scrollPosition = null;
    _hide();
    super.dispose();
  }

  Future<void> _triggerVibration() async {
    for (var i = 0; i < widget.vibrateCount; i++) {
      if (i > 0) {
        await Future.delayed(widget.vibrateInterval);
      }
      try {
        // 优先调用原生硬件马达通道（45ms 短促干脆反馈）
        // 华为手机（EMUI/HarmonyOS）对默认的 mediumImpact (VIRTUAL_KEY) 存在系统级静音策略，
        // 而硬件级 Vibrator 及 HapticFeedbackConstants.LONG_PRESS 均可直接驱动马达。
        await Native.vibrate(HapticFeedbackType.vibrate, 45);
      } catch (_) {
        try {
          await HapticFeedback.vibrate();
        } catch (_) {
          await HapticFeedback.mediumImpact();
        }
      }
    }
  }

  void _show() {
    if (_entry != null || !mounted) return;
    _activePopovers.add(this);
    if (widget.vibrate && widget.vibrateCount > 0) {
      _triggerVibration();
    }
    final render = context.findRenderObject() as RenderBox?;
    if (render == null || !render.hasSize) return;

    final overlay = Overlay.of(context, rootOverlay: true);
    final overlayRender = overlay.context.findRenderObject() as RenderBox?;
    final target = overlayRender == null
        ? (render.localToGlobal(Offset.zero) & render.size)
        : (render.localToGlobal(Offset.zero, ancestor: overlayRender) &
            render.size);

    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final screenPadding = mediaQuery.padding;

    _entry = OverlayEntry(
      builder: (overlayContext) => Stack(
        children: [
          // 点击遮罩区域退出
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: widget.dismissOnTapOutside ? _hide : null,
            ),
          ),

          // 具备屏幕边界防溢出保护的浮层布局
          CustomSingleChildLayout(
            delegate: _FloatingPopoverLayoutDelegate(
              targetRect: target,
              screenSize: screenSize,
              screenPadding: screenPadding,
              placement: widget.placement,
              offset: widget.offset,
              screenMargin: widget.screenMargin,
            ),
            child: Focus(
              autofocus: widget.dismissOnEscape,
              onKeyEvent: (_, event) {
                if (widget.dismissOnEscape &&
                    event.logicalKey == LogicalKeyboardKey.escape) {
                  _hide();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: _PopoverCard(
                useCard: widget.useCard,
                child: widget.contentBuilder(overlayContext),
              ),
            ),
          ),
        ],
      ),
    );

    overlay.insert(_entry!);
    widget.controller?._setVisible(true);
  }

  void _hide() {
    _activePopovers.remove(this);
    _entry?.remove();
    _entry = null;
    widget.controller?._setVisible(false);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: widget.onLongPress ?? _show,
        onSecondaryTap: widget.onSecondaryTap ?? _show,
        child: widget.child,
      );
}

/// 屏幕边界防溢出计算代理。
class _FloatingPopoverLayoutDelegate extends SingleChildLayoutDelegate {
  _FloatingPopoverLayoutDelegate({
    required this.targetRect,
    required this.screenSize,
    required this.screenPadding,
    required this.placement,
    required this.offset,
    required this.screenMargin,
  });

  final Rect targetRect;
  final Size screenSize;
  final EdgeInsets screenPadding;
  final FloatingPlacement placement;
  final Offset offset;
  final double screenMargin;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    // 限制子元素最大不能超过可用安全屏幕尺寸
    final maxWidth = (screenSize.width - screenMargin * 2).clamp(0.0, double.infinity);
    final maxHeight = (screenSize.height -
            screenPadding.top -
            screenPadding.bottom -
            screenMargin * 2)
        .clamp(0.0, double.infinity);

    return BoxConstraints(
      maxWidth: maxWidth,
      maxHeight: maxHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    double x = 0;
    double y = 0;

    final safeLeft = screenMargin;
    final safeRight = screenSize.width - childSize.width - screenMargin;
    final safeTop = screenPadding.top + screenMargin;
    final safeBottom =
        screenSize.height - screenPadding.bottom - childSize.height - screenMargin;

    switch (placement) {
      case FloatingPlacement.avatar:
        // 头像菜单：不能盖住头像，在左侧或是在右侧
        // 1. 水平定位：
        // 若头像在左侧（如对方头像）：菜单展示在头像右侧（targetRect.right + offset.dx），完全不遮挡头像！
        // 若头像在右侧（如我方头像）：菜单展示在头像左侧（targetRect.left - childSize.width - offset.dx），完全不遮挡头像！
        if (targetRect.center.dx < screenSize.width / 2) {
          x = targetRect.right + offset.dx;
          // 若右侧可用空间不足（极窄屏），备选展示在左侧
          if (x + childSize.width > safeRight &&
              targetRect.left - childSize.width - offset.dx >= safeLeft) {
            x = targetRect.left - childSize.width - offset.dx;
          }
        } else {
          x = targetRect.left - childSize.width - offset.dx;
          // 若左侧可用空间不足，备选展示在右侧
          if (x < safeLeft &&
              targetRect.right + offset.dx + childSize.width <= safeRight) {
            x = targetRect.right + offset.dx;
          }
        }

        // 2. 垂直定位：
        // 默认与头像顶部对齐 + offset.dy：
        y = targetRect.top + offset.dy;
        // 如果在屏幕底部（y 超出了 safeBottom）：
        // 向上对齐（菜单底部与头像底部对齐 - offset.dy），确保不超出屏幕底部且不盖住头像！
        if (y > safeBottom) {
          y = targetRect.bottom - childSize.height - offset.dy;
        }
        break;

      case FloatingPlacement.left:
        x = targetRect.left - childSize.width - offset.dx;
        y = targetRect.top;
        if (y > safeBottom) y = targetRect.bottom - childSize.height;
        break;

      case FloatingPlacement.right:
        x = targetRect.right + offset.dx;
        y = targetRect.top;
        if (y > safeBottom) y = targetRect.bottom - childSize.height;
        break;

      case FloatingPlacement.top:
      case FloatingPlacement.topStart:
      case FloatingPlacement.topEnd:
        x = targetRect.center.dx - childSize.width / 2;
        y = targetRect.top - childSize.height - offset.dy;
        break;

      case FloatingPlacement.bottom:
      case FloatingPlacement.bottomStart:
      case FloatingPlacement.bottomEnd:
        x = targetRect.center.dx - childSize.width / 2;
        y = targetRect.bottom + offset.dy;
        break;

      case FloatingPlacement.auto:
        // 消息气泡菜单：
        // 1. 垂直：优先在气泡上方，若上方空间不足则在下方
        final spaceAbove = targetRect.top - safeTop;
        final spaceBelow = safeBottom + childSize.height - targetRect.bottom;
        if (spaceAbove >= childSize.height + offset.dy) {
          y = targetRect.top - childSize.height - offset.dy;
        } else if (spaceBelow >= childSize.height + offset.dy) {
          y = targetRect.bottom + offset.dy;
        } else {
          y = spaceAbove >= spaceBelow
              ? targetRect.top - childSize.height - offset.dy
              : targetRect.bottom + offset.dy;
        }

        // 2. 水平：以气泡为基准，偏右气泡右对齐，偏左气泡左对齐，中间气泡居中
        if (targetRect.center.dx > screenSize.width * 0.6) {
          x = targetRect.right - childSize.width;
        } else if (targetRect.center.dx < screenSize.width * 0.4) {
          x = targetRect.left;
        } else {
          x = targetRect.center.dx - childSize.width / 2;
        }
        break;
    }

    // 绝对防守：钳制在安全区域内，绝不超出屏幕外
    if (safeRight >= safeLeft) {
      x = x.clamp(safeLeft, safeRight);
    } else {
      x = safeLeft;
    }

    if (safeBottom >= safeTop) {
      y = y.clamp(safeTop, safeBottom);
    } else {
      y = safeTop;
    }

    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_FloatingPopoverLayoutDelegate oldDelegate) {
    return targetRect != oldDelegate.targetRect ||
        screenSize != oldDelegate.screenSize ||
        screenPadding != oldDelegate.screenPadding ||
        placement != oldDelegate.placement ||
        offset != oldDelegate.offset ||
        screenMargin != oldDelegate.screenMargin;
  }
}

class _PopoverCard extends StatelessWidget {
  const _PopoverCard({
    required this.child,
    this.useCard = false,
  });

  final Widget child;
  final bool useCard;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: .92, end: 1),
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          builder: (_, scale, child) => Transform.scale(
            scale: scale,
            child: Opacity(opacity: scale.clamp(0.0, 1.0), child: child),
          ),
          child: useCard
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 14,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: child,
                  ),
                )
              : child,
        ),
      );
}
