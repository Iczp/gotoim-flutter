import 'package:flutter/material.dart';

enum ChatBubbleSide { none, left, right }

enum ChatBubbleTailAlignment { top, center, bottom }

@immutable
class ChatBubbleTail {
  const ChatBubbleTail({
    this.enabled = true,
    this.width = 10,
    this.radius = 14,
    this.alignment = ChatBubbleTailAlignment.bottom,
    this.offset = -4,
    this.edgeInset = 2,
    this.cutRadius,
    this.cutOutsideOffset = 1,
    this.cutYOffset = -7,
  });
  const ChatBubbleTail.none()
    : enabled = false,
      width = 0,
      radius = 0,
      alignment = ChatBubbleTailAlignment.bottom,
      offset = 0,
      edgeInset = 0,
      cutRadius = null,
      cutOutsideOffset = 0,
      cutYOffset = 0;
  final bool enabled;
  final double width;
  final double radius;
  final ChatBubbleTailAlignment alignment;
  final double offset;
  final double edgeInset;
  final double? cutRadius;
  final double cutOutsideOffset;
  final double cutYOffset;
}

@immutable
class ChatBubbleStyle {
  const ChatBubbleStyle._({
    required this.side,
    required this.backgroundColor,
    required this.padding,
    required this.tail,
    required this.reserveTailSpace,
    this.borderColor,
    this.borderWidth = 0,
    this.elevation = 0,
    this.shadowColor = Colors.black26,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
  });
  factory ChatBubbleStyle.content({
    required ChatBubbleSide side,
    required Color backgroundColor,
    ChatBubbleTail tail = const ChatBubbleTail(),
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
      horizontal: 13,
      vertical: 9,
    ),
    Color? borderColor,
    double borderWidth = 0,
    double elevation = 0,
    Color shadowColor = Colors.black26,
    BorderRadius borderRadius = const BorderRadius.all(Radius.circular(14)),
  }) => ChatBubbleStyle._(
    side: side,
    backgroundColor: backgroundColor,
    padding: padding,
    tail: side == ChatBubbleSide.none ? const ChatBubbleTail.none() : tail,
    reserveTailSpace: true,
    borderColor: borderColor,
    borderWidth: borderWidth,
    elevation: elevation,
    shadowColor: shadowColor,
    borderRadius: borderRadius,
  );
  factory ChatBubbleStyle.media({
    required ChatBubbleSide side,
    required Color backgroundColor,
    ChatBubbleTail tail = const ChatBubbleTail(offset: -6),
    Color? borderColor,
    double borderWidth = 0,
    double elevation = 0,
    Color shadowColor = Colors.black26,
    BorderRadius borderRadius = const BorderRadius.all(Radius.circular(14)),
  }) => ChatBubbleStyle._(
    side: side,
    backgroundColor: backgroundColor,
    padding: EdgeInsets.zero,
    tail: side == ChatBubbleSide.none ? const ChatBubbleTail.none() : tail,
    reserveTailSpace: false,
    borderColor: borderColor,
    borderWidth: borderWidth,
    elevation: elevation,
    shadowColor: shadowColor,
    borderRadius: borderRadius,
  );
  final ChatBubbleSide side;
  final Color backgroundColor;
  final EdgeInsetsGeometry padding;
  final ChatBubbleTail tail;
  final bool reserveTailSpace;
  final Color? borderColor;
  final double borderWidth;
  final double elevation;
  final Color shadowColor;
  final BorderRadius borderRadius;
}

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    required this.style,
    required this.child,
    super.key,
    this.width,
    this.height,
    this.constraints,
    this.onTap,
    this.onLongPress,
    this.onDoubleTap,
  });
  final ChatBubbleStyle style;
  final Widget child;
  final double? width;
  final double? height;
  final BoxConstraints? constraints;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDoubleTap;
  @override
  Widget build(BuildContext context) {
    final inset =
        style.tail.enabled && style.reserveTailSpace ? style.tail.width : 0.0;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      onDoubleTap: onDoubleTap,
      child: ConstrainedBox(
        constraints: constraints ?? const BoxConstraints(),
        child: SizedBox(
          width: width,
          height: height,
          child: ClipPath(
            clipper: ChatBubbleClipper(style),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: style.backgroundColor,
                border:
                    style.borderColor == null
                        ? null
                        : Border.all(
                          color: style.borderColor!,
                          width: style.borderWidth,
                        ),
                boxShadow:
                    style.elevation == 0
                        ? null
                        : [
                          BoxShadow(
                            color: style.shadowColor,
                            blurRadius: style.elevation * 2,
                            offset: Offset(0, style.elevation / 2),
                          ),
                        ],
              ),
              child: Padding(
                padding: EdgeInsetsDirectional.only(
                  start: style.side == ChatBubbleSide.left ? inset : 0,
                  end: style.side == ChatBubbleSide.right ? inset : 0,
                ).add(style.padding),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ChatBubbleClipper extends CustomClipper<Path> {
  ChatBubbleClipper(this.style);
  final ChatBubbleStyle style;
  @override
  Path getClip(Size size) {
    final tail = style.tail;
    if (!tail.enabled || style.side == ChatBubbleSide.none || size.isEmpty) {
      return Path()..addRRect(style.borderRadius.toRRect(Offset.zero & size));
    }
    final width = tail.width.clamp(0, size.width / 2).toDouble();
    final body =
        style.side == ChatBubbleSide.left
            ? Rect.fromLTWH(width, 0, size.width - width, size.height)
            : Rect.fromLTWH(0, 0, size.width - width, size.height);
    var path = Path()..addRRect(style.borderRadius.toRRect(body));
    final radius = tail.radius.clamp(1, size.height / 2).toDouble();
    final base = switch (tail.alignment) {
      ChatBubbleTailAlignment.top => tail.edgeInset + radius,
      ChatBubbleTailAlignment.center => size.height / 2,
      ChatBubbleTailAlignment.bottom => size.height - tail.edgeInset - radius,
    };
    final cy =
        (base + tail.offset).clamp(radius, size.height - radius).toDouble();
    final outer = Offset(
      style.side == ChatBubbleSide.left ? radius : size.width - radius,
      cy,
    );
    path = Path.combine(
      PathOperation.union,
      path,
      Path()..addOval(Rect.fromCircle(center: outer, radius: radius)),
    );
    final cut = Offset(
      style.side == ChatBubbleSide.left
          ? -tail.cutOutsideOffset
          : size.width + tail.cutOutsideOffset,
      cy + tail.cutYOffset,
    );
    return Path.combine(
      PathOperation.difference,
      path,
      Path()..addOval(
        Rect.fromCircle(center: cut, radius: tail.cutRadius ?? radius + 1),
      ),
    );
  }

  @override
  bool shouldReclip(ChatBubbleClipper old) => old.style != style;
}
