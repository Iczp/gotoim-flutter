import 'package:flutter/material.dart';

import '../platform/windows/windows_window_adapter.dart';

/// Router builders sit above the route overlay. Tooltips in native chrome need
/// an overlay covering the whole frame, including the custom caption.
class DesktopToolWindowFrame extends StatelessWidget {
  const DesktopToolWindowFrame({
    required this.title,
    required this.onClose,
    required this.child,
    super.key,
  });
  final String title;
  final VoidCallback onClose;
  final Widget child;
  @override
  Widget build(BuildContext context) => Overlay.wrap(
    child: Column(
      children: [
        DesktopWindowTitleBar(title: title, onClose: onClose),
        Expanded(child: child),
      ],
    ),
  );
}

/// Shared chrome for native tool windows; routed content stays below it.
class DesktopWindowTitleBar extends StatefulWidget {
  const DesktopWindowTitleBar({
    required this.title,
    required this.onClose,
    this.leading,
    this.actions,
    this.showPin = true,
    this.showMinimize = true,
    this.showMaximize = true,
    this.allowDoubleClickMaximize = true,
    this.backgroundColor,
    this.height = 38,
    super.key,
  });
  final String title;
  final VoidCallback onClose;
  final Widget? leading;
  final List<Widget>? actions;
  final bool showPin;
  final bool showMinimize;
  final bool showMaximize;
  final bool allowDoubleClickMaximize;
  final Color? backgroundColor;
  final double height;

  @override
  State<DesktopWindowTitleBar> createState() => _DesktopWindowTitleBarState();
}

class _DesktopWindowTitleBarState extends State<DesktopWindowTitleBar> {
  bool _maximized = false;
  bool _pinned = false;
  bool _closeHovered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _maximized = WindowsWindowAdapter.isMaximized();
        });
      }
    });
  }

  Future<void> _toggleMaximize() async {
    await WindowsWindowAdapter.toggleMaximize();
    if (mounted) {
      setState(() => _maximized = WindowsWindowAdapter.isMaximized());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final defaultBg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFECECEC);

    return Material(
      color: widget.backgroundColor ?? defaultBg,
      child: SizedBox(
        height: widget.height,
        child: Row(
          children: [
            if (widget.leading != null) ...[
              const SizedBox(width: 12),
              widget.leading!,
            ],
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => WindowsWindowAdapter.startDragging(),
                onDoubleTap:
                    widget.allowDoubleClickMaximize ? _toggleMaximize : null,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: widget.leading != null ? 8 : 14,
                    right: 14,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
            if (widget.actions != null) ...widget.actions!,
            if (widget.showPin)
              IconButton(
                tooltip: _pinned ? '取消置顶' : '置顶',
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: Icon(
                  _pinned ? Icons.push_pin : Icons.push_pin_outlined,
                  size: 15,
                ),
                onPressed: () {
                  setState(() => _pinned = !_pinned);
                  WindowsWindowAdapter.setAlwaysOnTop(_pinned);
                },
              ),
            if (widget.showMinimize)
              IconButton(
                tooltip: '最小化',
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(Icons.remove_rounded, size: 15),
                onPressed: WindowsWindowAdapter.minimize,
              ),
            if (widget.showMaximize)
              IconButton(
                tooltip: _maximized ? '还原' : '最大化',
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: Icon(
                  _maximized
                      ? Icons.filter_none_rounded
                      : Icons.crop_square_rounded,
                  size: 14,
                ),
                onPressed: _toggleMaximize,
              ),
            MouseRegion(
              onEnter: (_) => setState(() => _closeHovered = true),
              onExit: (_) => setState(() => _closeHovered = false),
              child: InkWell(
                onTap: widget.onClose,
                child: Container(
                  width: 38,
                  height: widget.height,
                  alignment: Alignment.center,
                  color: _closeHovered
                      ? const Color(0xFFE81123)
                      : Colors.transparent,
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: _closeHovered
                        ? Colors.white
                        : (isDark ? Colors.white70 : Colors.black87),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
