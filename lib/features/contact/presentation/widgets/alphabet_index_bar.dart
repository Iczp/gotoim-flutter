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
  String? _draggingKey;
  String? _jumpTarget;
  String? _pendingKey;
  bool _selectionScheduled = false;

  void _selectAt(
    Offset localPosition, {
    required double alphabetHeight,
    required double jumpExtent,
    required bool showJumpIcons,
    required double verticalPadding,
  }) {
    if (widget.keys.isEmpty) return;
    final contentY = localPosition.dy - verticalPadding;

    if (showJumpIcons) {
      if (contentY < jumpExtent) {
        if (_jumpTarget == 'top') return;
        _jumpTarget = 'top';
        _stopDragging(clearJumpTarget: false);
        widget.onScrollToTop();
        return;
      }
      final alphabetEnd = jumpExtent + alphabetHeight;
      if (contentY >= alphabetEnd) {
        if (_jumpTarget == 'bottom') return;
        _jumpTarget = 'bottom';
        _stopDragging(clearJumpTarget: false);
        widget.onScrollToBottom();
        return;
      }
    }

    _jumpTarget = null;
    final alphabetY = showJumpIcons ? (contentY - jumpExtent) : contentY;
    if (alphabetHeight <= 0) return;
    final progress = (alphabetY / alphabetHeight).clamp(0.0, 0.9999);
    final index = (progress * widget.keys.length).floor().clamp(
      0,
      widget.keys.length - 1,
    );
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = constraints.maxHeight;
        if (maxHeight < 40 || widget.keys.isEmpty) {
          return const SizedBox.shrink();
        }

        final colors = Theme.of(context).colorScheme;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final shownKey = _draggingKey ?? widget.activeKey;
        final isTouching = _draggingKey != null;

        // 横屏或矮屏幕（< 340px）下隐藏上下跳转图标，把空间全部让渡给字母索引
        final bool showJumpIcons = maxHeight >= 340;
        final double verticalPadding = maxHeight < 240 ? 2.0 : 4.0;

        // 竖屏舒展高度 vs 横屏自适应高度
        const double standardItemExtent = 18.0;
        const double standardJumpExtent = 24.0;
        final double idealHeight =
            (showJumpIcons ? standardJumpExtent * 2 : 0.0) +
            widget.keys.length * standardItemExtent +
            verticalPadding * 2;

        final double containerHeight = idealHeight.clamp(40.0, maxHeight);
        final double availableContentHeight = (containerHeight - verticalPadding * 2).clamp(
          0.0,
          double.infinity,
        );

        final double jumpExtent = showJumpIcons
            ? (availableContentHeight / (widget.keys.length + 2.5)).clamp(14.0, 24.0)
            : 0.0;
        final double alphabetHeight =
            (availableContentHeight - (showJumpIcons ? jumpExtent * 2 : 0.0)).clamp(
              0.0,
              double.infinity,
            );

        final double itemExtent = alphabetHeight / widget.keys.length;

        // 自适应字体大小与稀疏采样间隔
        final double fontSize = (itemExtent * 0.72).clamp(7.5, 11.0).toDouble();
        final int step;
        if (itemExtent >= 13.5) {
          step = 1;
        } else if (itemExtent >= 9.0) {
          step = 1;
        } else if (itemExtent >= 5.5) {
          step = 2;
        } else {
          step = (14.0 / itemExtent.clamp(1.0, 14.0)).ceil().clamp(2, 4);
        }

        final double barWidth = maxHeight < 260 ? 24.0 : 28.0;

        return Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanDown: (details) => _selectAt(
              details.localPosition,
              alphabetHeight: alphabetHeight,
              jumpExtent: jumpExtent,
              showJumpIcons: showJumpIcons,
              verticalPadding: verticalPadding,
            ),
            onPanUpdate: (details) => _selectAt(
              details.localPosition,
              alphabetHeight: alphabetHeight,
              jumpExtent: jumpExtent,
              showJumpIcons: showJumpIcons,
              verticalPadding: verticalPadding,
            ),
            onPanEnd: (_) => _stopDragging(),
            onPanCancel: _stopDragging,
            onTapUp: (_) => _stopDragging(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              width: barWidth,
              height: containerHeight,
              decoration: BoxDecoration(
                color: colors.surface.withValues(
                  alpha: isTouching ? (isDark ? .92 : .90) : (isDark ? .30 : .20),
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isTouching
                      ? colors.outlineVariant.withValues(alpha: .5)
                      : Colors.transparent,
                  width: 0.5,
                ),
                boxShadow: isTouching
                    ? <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? .35 : .12,
                          ),
                          blurRadius: 8,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  vertical: verticalPadding,
                  horizontal: 1,
                ),
                child: Column(
                  children: <Widget>[
                    if (showJumpIcons)
                      AlphabetJumpIcon(
                        icon: Icons.vertical_align_top_rounded,
                        extent: jumpExtent,
                        width: barWidth,
                      ),
                    for (var i = 0; i < widget.keys.length; i++)
                      Expanded(
                        child: _buildIndexItem(
                          key: widget.keys[i],
                          index: i,
                          totalCount: widget.keys.length,
                          step: step,
                          barWidth: barWidth,
                          fontSize: fontSize,
                          shownKey: shownKey,
                          isTouching: isTouching,
                          colors: colors,
                        ),
                      ),
                    if (showJumpIcons)
                      AlphabetJumpIcon(
                        icon: Icons.vertical_align_bottom_rounded,
                        extent: jumpExtent,
                        width: barWidth,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildIndexItem({
    required String key,
    required int index,
    required int totalCount,
    required int step,
    required double barWidth,
    required double fontSize,
    required String shownKey,
    required bool isTouching,
    required ColorScheme colors,
  }) {
    final bool isHighlighted = key == shownKey;
    // 首尾项始终显示文字，正在激活拖拽中的项始终显示文字；其余项按 step 采样，未采样的显示微型圆点
    final bool showText =
        step == 1 ||
        index == 0 ||
        index == totalCount - 1 ||
        index % step == 0 ||
        isHighlighted;

    final dotColor = colors.onSurfaceVariant.withValues(
      alpha: isTouching ? .65 : .38,
    );

    return SizedBox(
      width: barWidth,
      child: Center(
        child: showText
            ? Text(
                key,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: TextStyle(
                  fontSize: fontSize,
                  height: 1.0,
                  fontWeight:
                      isHighlighted ? FontWeight.w800 : FontWeight.w500,
                  color: isHighlighted
                      ? colors.primary.withValues(alpha: isTouching ? 1 : .75)
                      : colors.onSurfaceVariant.withValues(
                          alpha: isTouching ? .92 : .45,
                        ),
                ),
              )
            : Container(
                width: 2.5,
                height: 2.5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dotColor,
                ),
              ),
      ),
    );
  }
}

class AlphabetJumpIcon extends StatelessWidget {
  const AlphabetJumpIcon({
    required this.icon,
    this.extent = 26.0,
    this.width = 28.0,
    super.key,
  });

  final IconData icon;
  final double extent;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final iconSize = (extent * 0.65).clamp(11.0, 16.0).toDouble();
    return SizedBox(
      width: width,
      height: extent,
      child: Center(
        child: Icon(
          icon,
          size: iconSize,
          color: colors.onSurfaceVariant.withValues(alpha: .42),
        ),
      ),
    );
  }
}
