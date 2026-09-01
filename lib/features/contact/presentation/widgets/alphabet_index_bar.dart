import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class AlphabetIndexBar extends StatefulWidget {
  const AlphabetIndexBar({
    required this.keys,
    required this.activeKey,
    required this.onSelected,
    required this.onScrollToTop,
    required this.onScrollToBottom,
    required this.onDragging,
    super.key,
  });

  final List<String> keys;
  final String activeKey;
  final ValueChanged<String> onSelected;
  final VoidCallback onScrollToTop;
  final VoidCallback onScrollToBottom;
  final ValueChanged<String?> onDragging;

  @override
  State<AlphabetIndexBar> createState() => _AlphabetIndexBarState();
}

class _AlphabetIndexBarState extends State<AlphabetIndexBar> {
  static const _itemExtent = 19.0;
  static const _jumpItemExtent = 26.0;
  static const _verticalPadding = 4.0;
  String? _draggingKey;
  String? _jumpTarget;
  String? _pendingKey;
  bool _selectionScheduled = false;

  void _selectAt(Offset localPosition) {
    if (widget.keys.isEmpty) return;
    final contentY = localPosition.dy - _verticalPadding;
    if (contentY < _jumpItemExtent) {
      if (_jumpTarget == 'top') return;
      _jumpTarget = 'top';
      _stopDragging(clearJumpTarget: false);
      widget.onScrollToTop();
      return;
    }
    final alphabetEnd = _jumpItemExtent + widget.keys.length * _itemExtent;
    if (contentY >= alphabetEnd) {
      if (_jumpTarget == 'bottom') return;
      _jumpTarget = 'bottom';
      _stopDragging(clearJumpTarget: false);
      widget.onScrollToBottom();
      return;
    }
    _jumpTarget = null;
    final rawIndex = ((contentY - _jumpItemExtent) / _itemExtent).floor();
    final index = rawIndex.clamp(0, widget.keys.length - 1).toInt();
    final key = widget.keys[index];
    if (key == _draggingKey) return;
    setState(() => _draggingKey = key);
    widget.onDragging(key);
    _scheduleSelection(key);
  }

  void _scheduleSelection(String key) {
    _pendingKey = key;
    if (_selectionScheduled) return;
    _selectionScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _selectionScheduled = false;
      final selectedKey = _pendingKey;
      _pendingKey = null;
      if (mounted && selectedKey != null) {
        widget.onSelected(selectedKey);
      }
    });
  }

  void _stopDragging({bool clearJumpTarget = true}) {
    if (clearJumpTarget) _jumpTarget = null;
    if (_draggingKey != null) {
      setState(() => _draggingKey = null);
      widget.onDragging(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shownKey = _draggingKey ?? widget.activeKey;
    final isTouching = _draggingKey != null;
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanDown: (details) => _selectAt(details.localPosition),
            onPanUpdate: (details) => _selectAt(details.localPosition),
            onPanEnd: (_) => _stopDragging(),
            onPanCancel: _stopDragging,
            onTapUp: (_) => _stopDragging(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: isTouching ? .88 : .22),
                borderRadius: BorderRadius.circular(16),
                boxShadow:
                    isTouching
                        ? <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .12),
                            blurRadius: 8,
                          ),
                        ]
                        : null,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: _verticalPadding,
                  horizontal: 2,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const AlphabetJumpIcon(icon: Icons.vertical_align_top_rounded),
                    ...widget.keys.map(
                      (key) => SizedBox(
                        width: 28,
                        height: _itemExtent,
                        child: Center(
                          child: Text(
                            key,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight:
                                  key == shownKey
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                              color:
                                  key == shownKey
                                      ? colors.primary.withValues(
                                        alpha: isTouching ? 1 : .56,
                                      )
                                      : colors.onSurfaceVariant.withValues(
                                        alpha: isTouching ? .9 : .36,
                                      ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const AlphabetJumpIcon(
                      icon: Icons.vertical_align_bottom_rounded,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AlphabetJumpIcon extends StatelessWidget {
  const AlphabetJumpIcon({required this.icon, super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 28,
      height: 26.0,
      child: Center(
        child: Icon(
          icon,
          size: 16,
          color: colors.onSurfaceVariant.withValues(alpha: .42),
        ),
      ),
    );
  }
}
