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
    this.showPin = true,
    this.showMinimize = true,
    this.showMaximize = true,
    this.allowDoubleClickMaximize = true,
    this.backgroundColor,
    super.key,
  });
  final String title;
  final VoidCallback onClose;
  final bool showPin;
  final bool showMinimize;
  final bool showMaximize;
  final bool allowDoubleClickMaximize;
  final Color? backgroundColor;

  @override
  State<DesktopWindowTitleBar> createState() => _DesktopWindowTitleBarState();
}

class _DesktopWindowTitleBarState extends State<DesktopWindowTitleBar> {
  bool _maximized = false;
  bool _pinned = false;

  Future<void> _toggleMaximize() async {
    await WindowsWindowAdapter.toggleMaximize();
    if (mounted) {
      setState(() => _maximized = WindowsWindowAdapter.isMaximized());
    }
  }

  @override
  Widget build(BuildContext context) => Material(
    color:
        widget.backgroundColor ??
        Theme.of(context).colorScheme.surfaceContainer,
    child: SizedBox(
      height: 42,
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => WindowsWindowAdapter.startDragging(),
              onDoubleTap:
                  widget.allowDoubleClickMaximize ? _toggleMaximize : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (widget.showPin)
            IconButton(
              tooltip: _pinned ? '取消置顶' : '置顶',
              icon: Icon(
                _pinned ? Icons.push_pin : Icons.push_pin_outlined,
                size: 16,
              ),
              onPressed: () {
                setState(() => _pinned = !_pinned);
                WindowsWindowAdapter.setAlwaysOnTop(_pinned);
              },
            ),
          if (widget.showMinimize)
            IconButton(
              tooltip: '最小化',
              icon: const Icon(Icons.remove, size: 16),
              onPressed: WindowsWindowAdapter.minimize,
            ),
          if (widget.showMaximize)
            IconButton(
              tooltip: _maximized ? '还原' : '最大化',
              icon: Icon(
                _maximized ? Icons.filter_none : Icons.crop_square,
                size: 16,
              ),
              onPressed: _toggleMaximize,
            ),
          IconButton(
            tooltip: '关闭',
            icon: const Icon(Icons.close, size: 17),
            onPressed: widget.onClose,
          ),
        ],
      ),
    ),
  );
}
