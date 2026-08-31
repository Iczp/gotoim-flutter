import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Keeps media message previews inside the chat bubble without changing their
/// original aspect ratio. These limits match the prior client behaviour.
abstract final class MediaMessageLayout {
  static Size sizeFor({
    required BoxConstraints constraints,
    required double fallbackAspectRatio,
    double? aspectRatio,
    double maxWidth = 240,
    double maxHeight = 180,
  }) {
    final ratio =
        aspectRatio != null && aspectRatio.isFinite && aspectRatio > 0
            ? aspectRatio
            : fallbackAspectRatio;
    final availableWidth =
        constraints.maxWidth.isFinite
            ? math.min(maxWidth, constraints.maxWidth)
            : maxWidth;
    final widthByHeight = maxHeight * ratio;
    if (widthByHeight <= availableWidth) {
      return Size(widthByHeight, maxHeight);
    }
    return Size(availableWidth, availableWidth / ratio);
  }
}
