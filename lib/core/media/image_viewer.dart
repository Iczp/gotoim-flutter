import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Professional image viewer with smart animated zoom, rotation, and gesture arbitration.
class ImageViewer extends StatefulWidget {
  const ImageViewer({
    required this.heroTag,
    required this.source,
    this.bytes,
    this.onScaleChanged,
    this.quarterTurns = 0,
    super.key,
  });

  final Object heroTag;
  final String source;
  final Uint8List? bytes;
  final ValueChanged<double>? onScaleChanged;
  final int quarterTurns;

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer>
    with SingleTickerProviderStateMixin {
  final TransformationController _transformController =
      TransformationController();
  late final AnimationController _animController;
  Animation<Matrix4>? _matrixAnimation;
  Offset _doubleTapPosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    _transformController.addListener(_onTransformChanged);
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        if (_matrixAnimation != null) {
          _transformController.value = _matrixAnimation!.value;
        }
      });
  }

  @override
  void dispose() {
    _animController.dispose();
    _transformController.removeListener(_onTransformChanged);
    _transformController.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final scale = _transformController.value.getMaxScaleOnAxis();
    widget.onScaleChanged?.call(scale);
  }

  void _onDoubleTapDown(TapDownDetails details) {
    _doubleTapPosition = details.localPosition;
  }

  void _onDoubleTap() {
    if (_animController.isAnimating) return;
    final currentScale = _transformController.value.getMaxScaleOnAxis();
    final Size size = context.size ?? const Size(400, 600);

    final double targetScale;
    if (currentScale < 1.8) {
      targetScale = 2.5;
    } else if (currentScale < 3.2) {
      targetScale = 4.0;
    } else {
      targetScale = 1.0;
    }

    final Matrix4 targetMatrix;
    if (targetScale <= 1.0) {
      targetMatrix = Matrix4.identity();
    } else {
      final double x = -_doubleTapPosition.dx * (targetScale - 1.0);
      final double y = -_doubleTapPosition.dy * (targetScale - 1.0);
      final double clampedX =
          x.clamp(size.width * (1.0 - targetScale), 0.0);
      final double clampedY =
          y.clamp(size.height * (1.0 - targetScale), 0.0);

      targetMatrix = Matrix4.identity()
        ..translate(clampedX, clampedY)
        ..scale(targetScale);
    }

    _matrixAnimation = Matrix4Tween(
      begin: _transformController.value,
      end: targetMatrix,
    ).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeInOutCubic,
      ),
    );

    _animController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final imageWidget =
        widget.bytes != null
            ? Image.memory(widget.bytes!, fit: BoxFit.contain)
            : Image.network(
              widget.source,
              fit: BoxFit.contain,
              errorBuilder:
                  (_, _, _) => const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white70,
                        size: 48,
                      ),
                      SizedBox(height: 8),
                      Text(
                        '图片加载失败',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
            );

    final currentScale = _transformController.value.getMaxScaleOnAxis();

    final content = RotatedBox(
      quarterTurns: widget.quarterTurns,
      child: Center(child: imageWidget),
    );

    return Hero(
      tag: widget.heroTag,
      child: Material(
        type: MaterialType.transparency,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onDoubleTapDown: _onDoubleTapDown,
          onDoubleTap: _onDoubleTap,
          child: InteractiveViewer(
            transformationController: _transformController,
            minScale: 1.0,
            maxScale: 5.0,
            scaleEnabled: true,
            panEnabled: currentScale > 1.02,
            onInteractionEnd: (_) => _onTransformChanged(),
            child: content,
          ),
        ),
      ),
    );
  }
}
