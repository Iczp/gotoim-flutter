import 'package:flutter/material.dart';

import 'floating_window_manager.dart';
import 'floating_window_models.dart';

class FloatingWindowDragRegion extends StatelessWidget {
  const FloatingWindowDragRegion({
    super.key,
    required this.child,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
  });
  final Widget child;
  final GestureDragStartCallback? onPanStart;
  final GestureDragUpdateCallback? onPanUpdate;
  final GestureDragEndCallback? onPanEnd;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onPanStart: onPanStart,
    onPanUpdate: onPanUpdate,
    onPanEnd: onPanEnd,
    child: child,
  );
}

class FloatingWindowView extends StatefulWidget {
  const FloatingWindowView({
    super.key,
    required this.entry,
    required this.manager,
    required this.bounds,
  });
  final FloatingWindowEntry entry;
  final FloatingWindowManager manager;
  final FloatingWindowBounds bounds;

  @override
  State<FloatingWindowView> createState() => _FloatingWindowViewState();
}

class _FloatingWindowViewState extends State<FloatingWindowView> {
  bool _dragging = false;

  void _start(DragStartDetails details) {
    if (!widget.entry.options.draggable) return;
    setState(() => _dragging = true);
    widget.manager.bringToFront(widget.entry.id);
  }

  void _update(DragUpdateDetails details) {
    if (!widget.entry.options.draggable) return;
    final position = widget.bounds.clampPosition(
      widget.entry.position + details.delta,
      widget.entry.size,
    );
    widget.manager.updatePosition(widget.entry.id, position);
  }

  void _end(DragEndDetails details) {
    if (!_dragging) return;
    setState(() => _dragging = false);
    final options = widget.entry.options;
    if (!options.snapToEdge) return;
    final current = widget.entry.position;
    final leftDistance = current.dx - widget.bounds.rect.left;
    final rightDistance =
        widget.bounds.rect.right - (current.dx + widget.entry.size.width);
    final x =
        leftDistance <= rightDistance
            ? widget.bounds.rect.left
            : widget.bounds.rect.right - widget.entry.size.width;
    widget.manager.updatePosition(widget.entry.id, Offset(x, current.dy));
  }

  void _resize(DragUpdateDetails details) {
    final options = widget.entry.options;
    if (!options.resizable) return;
    var next = widget.entry.size + Offset(details.delta.dx, details.delta.dy);
    final maximum = Size(
      widget.bounds.rect.right - widget.entry.position.dx,
      widget.bounds.rect.bottom - widget.entry.position.dy,
    );
    next = Size(next.width, next.height);
    next = widget.bounds.clampSize(next, options);
    next = Size(
      next.width.clamp(options.minSize.width, maximum.width).toDouble(),
      next.height.clamp(options.minSize.height, maximum.height).toDouble(),
    );
    widget.manager.updateSize(widget.entry.id, next);
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final dragHandlers = (
      onPanStart: _start,
      onPanUpdate: _update,
      onPanEnd: _end,
    );
    final content =
        entry.contentMode == FloatingWindowContentMode.platformView
            ? Column(
              children: [
                FloatingWindowDragRegion(
                  onPanStart: dragHandlers.onPanStart,
                  onPanUpdate: dragHandlers.onPanUpdate,
                  onPanEnd: dragHandlers.onPanEnd,
                  child: _PlatformHeader(entry: entry, manager: widget.manager),
                ),
                Expanded(child: entry.child),
              ],
            )
            : FloatingWindowDragRegion(
              onPanStart: dragHandlers.onPanStart,
              onPanUpdate: dragHandlers.onPanUpdate,
              onPanEnd: dragHandlers.onPanEnd,
              child: entry.child,
            );
    return AnimatedPositioned(
      duration: _dragging ? Duration.zero : entry.options.snapDuration,
      curve: Curves.easeOut,
      left: entry.position.dx,
      top: entry.position.dy,
      width: entry.size.width,
      height: entry.size.height,
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onTap: () => widget.manager.bringToFront(entry.id),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 12),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  Positioned.fill(child: content),
                  if (entry.options.resizable)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onPanStart:
                            (_) => widget.manager.bringToFront(entry.id),
                        onPanUpdate: _resize,
                        child: const SizedBox(
                          width: 28,
                          height: 28,
                          child: Icon(Icons.drag_handle, size: 18),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlatformHeader extends StatelessWidget {
  const _PlatformHeader({required this.entry, required this.manager});
  final FloatingWindowEntry entry;
  final FloatingWindowManager manager;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: SizedBox(
      height: 34,
      child: Row(
        children: [
          const SizedBox(width: 8),
          const Icon(Icons.drag_indicator, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(entry.id, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            tooltip: '关闭浮窗',
            visualDensity: VisualDensity.compact,
            onPressed: () => manager.close(entry.id),
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    ),
  );
}
