import 'package:flutter/material.dart';

enum ParametricBubbleSide { left, right }

enum ParametricBubbleAnchor { top, bottom }

/// Deterministic parameters for a chat bubble with an inverted S-curve tail.
class ParametricBubbleConfig {
  const ParametricBubbleConfig({
    this.side = ParametricBubbleSide.left,
    this.anchor = ParametricBubbleAnchor.top,
    this.lineABBend = 1,
    this.lineACBend = 1,
    this.offset = 10,
    this.tailLength = 16,
    this.tailHeight = 18,
    this.inversion = .65,
    this.sharpness = .90,
    this.radius = 16,
  });

  final ParametricBubbleSide side;
  final ParametricBubbleAnchor anchor;

  /// Arc direction for line A-B: -1 is upward; 1 is downward.
  /// A is the tail apex and B is the upper/root attachment point.
  final double lineABBend;

  /// Arc direction for line A-C: -1 is upward; 1 is downward.
  /// A is the tail apex and C is the lower/root attachment point.
  final double lineACBend;
  final double offset;
  final double tailLength;
  final double tailHeight;
  final double inversion;
  final double sharpness;
  final double radius;

  ParametricBubbleConfig copyWith({
    ParametricBubbleSide? side,
    ParametricBubbleAnchor? anchor,
    double? lineABBend,
    double? lineACBend,
    double? offset,
    double? tailLength,
    double? tailHeight,
    double? inversion,
    double? sharpness,
    double? radius,
  }) => ParametricBubbleConfig(
    side: side ?? this.side,
    anchor: anchor ?? this.anchor,
    lineABBend: (lineABBend ?? this.lineABBend).clamp(-1, 1).toDouble(),
    lineACBend: (lineACBend ?? this.lineACBend).clamp(-1, 1).toDouble(),
    offset: (offset ?? this.offset).clamp(0, 100).toDouble(),
    tailLength: (tailLength ?? this.tailLength).clamp(4, 48).toDouble(),
    tailHeight: (tailHeight ?? this.tailHeight).clamp(8, 48).toDouble(),
    inversion: (inversion ?? this.inversion).clamp(0, 1).toDouble(),
    sharpness: (sharpness ?? this.sharpness).clamp(0, 1).toDouble(),
    radius: (radius ?? this.radius).clamp(4, 40).toDouble(),
  );

  Map<String, Object> toJson() => <String, Object>{
    'side': side.name,
    'anchor': anchor.name,
    'lineABBend': _rounded(lineABBend),
    'lineACBend': _rounded(lineACBend),
    'offset': _rounded(offset),
    'tailLength': _rounded(tailLength),
    'tailHeight': _rounded(tailHeight),
    'inversion': _rounded(inversion),
    'sharpness': _rounded(sharpness),
    'radius': _rounded(radius),
  };

  static double _rounded(double value) => (value * 100).roundToDouble() / 100;
}

/// A bubble body plus a continuously curved, inverted S-curve tail.
class ParametricChatBubble extends StatelessWidget {
  const ParametricChatBubble({
    required this.config,
    required this.color,
    required this.child,
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
  });

  final ParametricBubbleConfig config;
  final Color color;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final tailInset = config.tailLength.clamp(4, 48).toDouble();
    return CustomPaint(
      painter: _ParametricBubblePainter(config: config, color: color),
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: config.side == ParametricBubbleSide.left ? tailInset : 0,
          end: config.side == ParametricBubbleSide.right ? tailInset : 0,
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class _ParametricBubblePainter extends CustomPainter {
  const _ParametricBubblePainter({required this.config, required this.color});

  final ParametricBubbleConfig config;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final length = config.tailLength.clamp(4, 48).toDouble();
    final body = Rect.fromLTWH(
      config.side == ParametricBubbleSide.left ? length : 0,
      0,
      (size.width - length).clamp(0, double.infinity).toDouble(),
      size.height,
    );
    if (body.width <= 0 || body.height <= 0) return;
    final maxRadius = (body.shortestSide / 2).clamp(4, 40).toDouble();
    final radius = config.radius.clamp(4, maxRadius).toDouble();
    final path =
        Path()
          ..addRRect(RRect.fromRectAndRadius(body, Radius.circular(radius)))
          ..addPath(_tailPath(body, length, radius), Offset.zero);
    canvas.drawPath(path, Paint()..color = color);
  }

  Path _tailPath(Rect body, double length, double radius) {
    final height = config.tailHeight.clamp(8, 48).toDouble();
    final available =
        (body.height - radius * 2 - height)
            .clamp(0, double.infinity)
            .toDouble();
    final offset = config.offset.clamp(0, 100).clamp(0, available).toDouble();
    final top =
        config.anchor == ParametricBubbleAnchor.top
            ? radius + offset
            : body.height - radius - offset - height;
    final start = Offset(
      config.side == ParametricBubbleSide.left ? body.left : body.right,
      top,
    );
    final end = Offset(start.dx, top + height);
    final direction = config.side == ParametricBubbleSide.left ? -1.0 : 1.0;
    final apex = Offset(start.dx + direction * length, top + height / 2);
    // Inversion pulls the root back into the body.  The deliberately wide
    // range makes the inverted S bend evident even on compact message bubbles.
    final inversion = config.inversion.clamp(0, 1).toDouble();
    final sharpness = config.sharpness.clamp(0, 1).toDouble();
    final rootInset = length * (.06 + inversion * .52);

    // Higher sharpness places the cubic control points almost on the apex,
    // producing a thin, crisp pick. Lower values keep a softer rounded tip.
    final apexReach = length * (.015 + (1 - sharpness) * .58);
    final lineABBend = config.lineABBend.clamp(-1, 1).toDouble();
    final lineACBend = config.lineACBend.clamp(-1, 1).toDouble();
    // Give A-B / A-C a deliberately broad vertical range. Their independent
    // bend values are the visual control exposed by the diagnostic tuner, so
    // ±1 must produce an unmistakable large arc rather than a subtle wobble.
    final rootBend = height * (.18 + inversion * .52);
    final apexBend = height * (.18 + (1 - sharpness) * .36);
    final path = Path()..moveTo(start.dx, start.dy);
    path.cubicTo(
      start.dx - direction * rootInset,
      start.dy + lineABBend * rootBend,
      apex.dx - direction * apexReach,
      apex.dy + lineABBend * apexBend,
      apex.dx,
      apex.dy,
    );
    path.cubicTo(
      apex.dx - direction * apexReach,
      apex.dy + lineACBend * apexBend,
      end.dx - direction * rootInset,
      end.dy + lineACBend * rootBend,
      end.dx,
      end.dy,
    );
    return path..close();
  }

  @override
  bool shouldRepaint(_ParametricBubblePainter oldDelegate) =>
      oldDelegate.config != config || oldDelegate.color != color;
}
