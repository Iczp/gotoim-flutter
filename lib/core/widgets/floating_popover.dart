import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum FloatingPlacement {
  auto,
  top,
  bottom,
  left,
  right,
  topStart,
  topEnd,
  bottomStart,
  bottomEnd,
}

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
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;
  @override
  State<FloatingPopover> createState() => _FloatingPopoverState();
}

class _FloatingPopoverState extends State<FloatingPopover> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _entry;
  @override
  void initState() {
    super.initState();
    widget.controller?._bind(_show, _hide);
  }

  @override
  void didUpdateWidget(FloatingPopover oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.controller?._bind(_show, _hide);
  }

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  void _show() {
    if (_entry != null || !mounted) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    final render = context.findRenderObject() as RenderBox?;
    final screen = MediaQuery.sizeOf(context);
    final target =
        render == null
            ? Rect.zero
            : render.localToGlobal(Offset.zero) & render.size;
    final place = _resolvePlacement(target, screen);
    _entry = OverlayEntry(
      builder:
          (overlayContext) => Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: widget.dismissOnTapOutside ? _hide : null,
                ),
              ),
              CompositedTransformFollower(
                link: _link,
                showWhenUnlinked: false,
                targetAnchor: _targetAnchor(place),
                followerAnchor: _followerAnchor(place),
                offset: _placementOffset(place),
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
    _entry?.remove();
    _entry = null;
    widget.controller?._setVisible(false);
  }

  FloatingPlacement _resolvePlacement(Rect target, Size screen) {
    if (widget.placement != FloatingPlacement.auto) return widget.placement;
    return target.top > screen.height - target.bottom
        ? FloatingPlacement.top
        : FloatingPlacement.bottom;
  }

  Alignment _targetAnchor(FloatingPlacement p) => switch (p) {
    FloatingPlacement.top ||
    FloatingPlacement.topStart ||
    FloatingPlacement.topEnd => Alignment.topCenter,
    FloatingPlacement.left => Alignment.centerLeft,
    FloatingPlacement.right => Alignment.centerRight,
    _ => Alignment.bottomCenter,
  };
  Alignment _followerAnchor(FloatingPlacement p) => switch (p) {
    FloatingPlacement.top ||
    FloatingPlacement.topStart ||
    FloatingPlacement.topEnd => Alignment.bottomCenter,
    FloatingPlacement.left => Alignment.centerRight,
    FloatingPlacement.right => Alignment.centerLeft,
    _ => Alignment.topCenter,
  };
  Offset _placementOffset(FloatingPlacement p) => switch (p) {
    FloatingPlacement.top ||
    FloatingPlacement.topStart ||
    FloatingPlacement.topEnd => Offset(widget.offset.dx, -widget.offset.dy),
    FloatingPlacement.left => Offset(-widget.offset.dy, widget.offset.dx),
    FloatingPlacement.right => Offset(widget.offset.dy, widget.offset.dx),
    _ => widget.offset,
  };
  @override
  Widget build(BuildContext context) => CompositedTransformTarget(
    link: _link,
    child: GestureDetector(
      onLongPress: widget.onLongPress ?? _show,
      onSecondaryTap: widget.onSecondaryTap ?? _show,
      child: widget.child,
    ),
  );
}

class _PopoverCard extends StatelessWidget {
  const _PopoverCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: .95, end: 1),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      builder:
          (_, scale, child) => Transform.scale(
            scale: scale,
            child: Opacity(opacity: scale, child: child),
          ),
      child: DecoratedBox(
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
        child: Padding(padding: const EdgeInsets.all(6), child: child),
      ),
    ),
  );
}
