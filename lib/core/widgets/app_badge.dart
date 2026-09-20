import 'dart:ui';
import 'package:flutter/material.dart';

/// 角标尺寸类型
enum AppBadgeSize {
  /// 标准尺寸（高 20px，字体 12px）
  normal,

  /// 小型尺寸（高 16px，字体 10px）
  small,
}

/// Ant Design / Antdv 风格的动效角标组件
///
/// 特性：
/// 1. **数字转动动画（ScrollNumber）**：每个数位独立滚柱滚动。
///    数值增加时（如 19 → 20），十位 1→2 向上翻滚，个位 9→0 向上翻滚；
///    数值减少时向下反向翻滚。
/// 2. **进退场动画**：从 0 到有数值时弹性放大出现（`Curves.easeOutBack`）；
///    归 0 时缩放淡出消失。
/// 3. **位数平滑伸缩**：个位变两位（9 → 10）时，高位平滑展开并淡入，胶囊外框平滑自适应。
/// 4. **小红点（Dot）模式**：支持仅显示小红点并支持弹性出现/隐藏。
/// 5. **双重形态**：既可作为独立的行内 Badge（不传 [child]），也可作为悬浮角标贴在 [child] 右上角。
class AppBadge extends StatefulWidget {
  const AppBadge({
    super.key,
    this.count,
    this.dot = false,
    this.maxCount = 99,
    this.showZero = false,
    this.color,
    this.textColor,
    this.borderColor,
    this.borderWidth = 1.5,
    this.offset,
    this.size = AppBadgeSize.normal,
    this.child,
  });

  /// 角标展示的数字。为 null 或 <= 0 时（且未开启 [showZero] 且非 [dot]）会触发淡出隐藏。
  final int? count;

  /// 是否仅作为小红点展示。
  final bool dot;

  /// 最大展示数字，超出时展示为 "$maxCount+"，默认 99。
  final int maxCount;

  /// 当 [count] 为 0 时是否展示，默认 false。
  final bool showZero;

  /// 角标背景色，默认 `#FF4D4F`（Antd 经典危险红）。
  final Color? color;

  /// 字符文本颜色，默认白色。
  final Color? textColor;

  /// 边框颜色，默认白色（在纯色或复杂头像背景上凸显轮廓）。设为透明可去除边框。
  final Color? borderColor;

  /// 边框粗细，默认 1.5px。
  final double borderWidth;

  /// 悬浮角标相对右上角的偏移量。仅在提供 [child] 时生效。
  final Offset? offset;

  /// 尺寸级别，默认 [AppBadgeSize.normal]。
  final AppBadgeSize size;

  /// 被悬浮包裹的子组件（如头像、图标）。如果不传则作为独立的 Badge 渲染。
  final Widget? child;

  @override
  State<AppBadge> createState() => _AppBadgeState();
}

class _AppBadgeState extends State<AppBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _visibilityController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;

  late bool _isVisible;

  @override
  void initState() {
    super.initState();
    _isVisible = _computeVisible();

    _visibilityController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      value: _isVisible ? 1.0 : 0.0,
    );

    _scaleAnimation = CurvedAnimation(
      parent: _visibilityController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInBack,
    );

    _opacityAnimation = CurvedAnimation(
      parent: _visibilityController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
  }

  bool _computeVisible() {
    if (widget.dot) return true;
    final c = widget.count;
    if (c == null) return false;
    if (c < 0) return false;
    if (c == 0) return widget.showZero;
    return true;
  }

  @override
  void didUpdateWidget(AppBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nowVisible = _computeVisible();
    if (nowVisible != _isVisible) {
      _isVisible = nowVisible;
      if (_isVisible) {
        _visibilityController.forward();
      } else {
        _visibilityController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _visibilityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badgeColor = widget.color ?? const Color(0xFFFF4D4F);
    final badgeBorderColor =
        widget.borderColor ??
        (theme.brightness == Brightness.dark
            ? theme.colorScheme.surface
            : Colors.white);

    final badgeCore = AnimatedBuilder(
      animation: _visibilityController,
      builder: (context, child) {
        if (_visibilityController.value == 0.0) {
          return const SizedBox.shrink();
        }
        return ScaleTransition(
          scale: _scaleAnimation,
          alignment: Alignment.center,
          child: FadeTransition(
            opacity: _opacityAnimation,
            child: _BadgePill(
              count: widget.count,
              dot: widget.dot,
              maxCount: widget.maxCount,
              showZero: widget.showZero,
              color: badgeColor,
              textColor: widget.textColor ?? Colors.white,
              borderColor: badgeBorderColor,
              borderWidth: widget.borderWidth,
              size: widget.size,
            ),
          ),
        );
      },
    );

    // 如果未传 child，直接作为行内组件返回
    if (widget.child == null) {
      return badgeCore;
    }

    // 当完全不可见且动画在起始位置时，直接返回 child，不产生任何多余布局开销
    return AnimatedBuilder(
      animation: _visibilityController,
      builder: (context, _) {
        if (_visibilityController.value == 0.0) {
          return widget.child!;
        }

        final defaultOffset =
            widget.size == AppBadgeSize.small
                ? const Offset(6, -6)
                : const Offset(8, -8);
        final effectiveOffset = widget.offset ?? defaultOffset;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            widget.child!,
            Positioned(
              top: effectiveOffset.dy,
              right: -effectiveOffset.dx,
              child: badgeCore,
            ),
          ],
        );
      },
    );
  }
}

/// 胶囊底座与滚轮数字包装
class _BadgePill extends StatelessWidget {
  const _BadgePill({
    required this.count,
    required this.dot,
    required this.maxCount,
    required this.showZero,
    required this.color,
    required this.textColor,
    required this.borderColor,
    required this.borderWidth,
    required this.size,
  });

  final int? count;
  final bool dot;
  final int maxCount;
  final bool showZero;
  final Color color;
  final Color textColor;
  final Color borderColor;
  final double borderWidth;
  final AppBadgeSize size;

  @override
  Widget build(BuildContext context) {
    if (dot) {
      final dotDiameter = size == AppBadgeSize.small ? 6.0 : 8.0;
      return Container(
        width: dotDiameter + borderWidth * 2,
        height: dotDiameter + borderWidth * 2,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: borderColor, width: borderWidth),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
          ],
        ),
      );
    }

    final height = size == AppBadgeSize.small ? 16.0 : 20.0;
    final minWidth = height;
    final fontSize = size == AppBadgeSize.small ? 10.0 : 12.0;

    final effectiveCount = count ?? 0;
    final isOverflow = effectiveCount > maxCount;
    final text = isOverflow ? '$maxCount+' : '$effectiveCount';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      height: height,
      constraints: BoxConstraints(minWidth: minWidth),
      padding: EdgeInsets.symmetric(
        horizontal: text.length <= 1 ? 0 : (size == AppBadgeSize.small ? 4 : 6),
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(height / 2),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: const [
          BoxShadow(
            color: Color(0x29000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        widthFactor: 1.0,
        heightFactor: 1.0,
        child: _ScrollNumber(
          text: text,
          count: effectiveCount,
          fontSize: fontSize,
          height: height - borderWidth * 2,
          textColor: textColor,
        ),
      ),
    );
  }
}

/// Antdv 风格的滚轮数字动画控制器
class _ScrollNumber extends StatefulWidget {
  const _ScrollNumber({
    required this.text,
    required this.count,
    required this.fontSize,
    required this.height,
    required this.textColor,
  });

  final String text;
  final int count;
  final double fontSize;
  final double height;
  final Color textColor;

  @override
  State<_ScrollNumber> createState() => _ScrollNumberState();
}

class _ScrollNumberState extends State<_ScrollNumber>
    with SingleTickerProviderStateMixin {
  late AnimationController _rollController;
  late Animation<double> _rollAnimation;

  late String _currentText;
  late int _currentCount;
  String? _previousText;
  int _direction = 1; // 1 为增加（向上滚出），-1 为减少（向下滚出）

  @override
  void initState() {
    super.initState();
    _currentText = widget.text;
    _currentCount = widget.count;

    _rollController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _rollAnimation = CurvedAnimation(
      parent: _rollController,
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void didUpdateWidget(_ScrollNumber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != _currentText || widget.count != _currentCount) {
      _previousText = _currentText;
      _direction = widget.count >= _currentCount ? 1 : -1;
      _currentText = widget.text;
      _currentCount = widget.count;

      _rollController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _rollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(
      color: widget.textColor,
      fontSize: widget.fontSize,
      fontWeight: FontWeight.w600,
      height: 1.0,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final prev = _previousText ?? _currentText;
    final next = _currentText;

    // 从右往左对齐数字（个位对应个位，十位对应十位）
    final maxLen = prev.length > next.length ? prev.length : next.length;
    final paddedPrev = prev.padLeft(maxLen, ' ');
    final paddedNext = next.padLeft(maxLen, ' ');

    return AnimatedBuilder(
      animation: _rollAnimation,
      builder: (context, _) {
        final progress = _rollAnimation.value;
        final isAnimating = _rollController.isAnimating;

        final columns = <Widget>[];

        for (var i = 0; i < maxLen; i++) {
          final pChar = paddedPrev[i];
          final nChar = paddedNext[i];

          columns.add(
            _RollColumn(
              prevChar: pChar == ' ' ? '' : pChar,
              nextChar: nChar == ' ' ? '' : nChar,
              direction: _direction,
              progress: isAnimating ? progress : 1.0,
              style: textStyle,
              height: widget.height,
            ),
          );
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: columns,
        );
      },
    );
  }
}

/// 单个字符的滚柱槽
class _RollColumn extends StatelessWidget {
  const _RollColumn({
    required this.prevChar,
    required this.nextChar,
    required this.direction,
    required this.progress,
    required this.style,
    required this.height,
  });

  final String prevChar;
  final String nextChar;
  final int direction;
  final double progress;
  final TextStyle style;
  final double height;

  @override
  Widget build(BuildContext context) {
    // 字符没有变化
    if (prevChar == nextChar) {
      if (nextChar.isEmpty) {
        return const SizedBox.shrink();
      }
      return SizedBox(
        height: height,
        child: Center(child: Text(nextChar, style: style)),
      );
    }

    // 字符有变化，制作垂直滚轮：
    // 当 direction == 1（增加）：旧字符向上滑出（0 -> -1），新字符从下方滑入（1 -> 0）
    // 当 direction == -1（减少）：旧字符向下滑出（0 -> 1），新字符从上方滑入（-1 -> 0）
    final prevOffset = -direction * progress;
    final nextOffset = direction * (1.0 - progress);

    final prevOpacity = (1.0 - progress).clamp(0.0, 1.0);
    final nextOpacity = progress.clamp(0.0, 1.0);

    // 位数展开/折叠动画（如 9 -> 10 时十位从无到有）
    double widthFactor = 1.0;
    if (prevChar.isEmpty && nextChar.isNotEmpty) {
      widthFactor = progress;
    } else if (prevChar.isNotEmpty && nextChar.isEmpty) {
      widthFactor = 1.0 - progress;
    }

    return ClipRect(
      child: Align(
        alignment: Alignment.center,
        widthFactor: widthFactor,
        child: SizedBox(
          height: height,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 旧字符
              if (prevChar.isNotEmpty && prevOpacity > 0.01)
                Transform.translate(
                  offset: Offset(0, prevOffset * height),
                  child: Opacity(
                    opacity: prevOpacity,
                    child: Text(prevChar, style: style),
                  ),
                ),
              // 新字符
              if (nextChar.isNotEmpty && nextOpacity > 0.01)
                Transform.translate(
                  offset: Offset(0, nextOffset * height),
                  child: Opacity(
                    opacity: nextOpacity,
                    child: Text(nextChar, style: style),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
