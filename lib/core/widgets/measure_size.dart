import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A render-object widget that notifies whenever its child widget's rendered size changes.
class MeasureSize extends SingleChildRenderObjectWidget {
  const MeasureSize({
    required this.onSizeChanged,
    required super.child,
    super.key,
  });

  final ValueChanged<Size> onSizeChanged;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderMeasureSize(onSizeChanged);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderMeasureSize renderObject,
  ) {
    renderObject.onSizeChanged = onSizeChanged;
  }
}

class RenderMeasureSize extends RenderProxyBox {
  RenderMeasureSize(this.onSizeChanged);

  ValueChanged<Size> onSizeChanged;
  Size? _oldSize;

  @override
  void performLayout() {
    super.performLayout();
    final newSize = size;
    if (_oldSize == newSize) return;
    _oldSize = newSize;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onSizeChanged(newSize);
    });
  }
}
