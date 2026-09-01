import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Professional image viewer with two-finger scale & twist rotation (with automatic
/// 90-degree quadrant magnetic snapping, like system photo albums), focal double-tap
/// zoom, and gesture conflict prevention.
class ImageViewer extends StatefulWidget {
  const ImageViewer({
    required this.heroTag,
    required this.source,
    this.bytes,
    this.onScaleChanged,
    this.scaleSensitivity = 1.0,
    this.rotationSensitivity = 1.0,
    this.minScale = 1.0,
    this.maxScale = 5.0,
    super.key,
  });

  final Object heroTag;
  final String source;
  final Uint8List? bytes;
  final ValueChanged<double>? onScaleChanged;

  /// Sensitivity factor for two-finger distance zoom (default 1.0).
  final double scaleSensitivity;

  /// Sensitivity factor for two-finger twist rotation (default 1.0).
  final double rotationSensitivity;

  /// Minimum stable scale after release (default 1.0).
  final double minScale;

  /// Maximum stable scale after release (default 5.0).
  final double maxScale;

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer>
    with SingleTickerProviderStateMixin {
  double _scale = 1.0;
  double _baseScale = 1.0;

  double _rotation = 0.0; // In radians
  double _baseRotation = 0.0;

  Offset _translation = Offset.zero;
  Offset _baseTranslation = Offset.zero;

  Offset _doubleTapPosition = Offset.zero;

  late final AnimationController _animController;
  Animation<double>? _scaleAnimation;
  Animation<double>? _rotationAnimation;
  Animation<Offset>? _translationAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..addListener(() {
        setState(() {
          if (_scaleAnimation != null) _scale = _scaleAnimation!.value;
          if (_rotationAnimation != null) _rotation = _rotationAnimation!.value;
          if (_translationAnimation != null) {
            _translation = _translationAnimation!.value;
          }
        });
        widget.onScaleChanged?.call(_scale);
      });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _onScaleStart(ScaleStartDetails details) {
    _animController.stop();
    _baseScale = _scale;
    _baseRotation = _rotation;
    _baseTranslation = _translation;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final hasScaleChange = (details.scale - 1.0).abs() > 0.001;
    final hasRotationChange = details.rotation.abs() > 0.001;
    final isMultiTouch = details.pointerCount >= 2 || hasScaleChange || hasRotationChange;

    if (isMultiTouch) {
      // Two-finger pinch distance zoom & twist rotation with configurable sensitivity
      final effectiveScaleDelta = (details.scale - 1.0) * widget.scaleSensitivity;
      final rawScale = _baseScale * (1.0 + effectiveScaleDelta);
      _scale = rawScale.clamp(0.5, 7.0);

      final effectiveRotation = details.rotation * widget.rotationSensitivity;
      _rotation = _baseRotation + effectiveRotation;

      _translation = _baseTranslation + details.focalPointDelta;
      widget.onScaleChanged?.call(_scale);
      setState(() {});
    } else if (_scale > 1.05) {
      // Single finger panning when zoomed in
      _translation += details.focalPointDelta;
      setState(() {});
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    final size = context.size ?? const Size(400, 600);

    // Target scale clamping to configured min/max
    final targetScale = _scale.clamp(widget.minScale, widget.maxScale);

    // Snap rotation to nearest 90-degree quadrant (pi/2)
    const quarterTurn = math.pi / 2;
    final targetQuarter = (_rotation / quarterTurn).round();
    final targetRotation = targetQuarter * quarterTurn;

    // Translation clamping to viewport boundaries
    final maxDx = (size.width * (targetScale - 1.0)) / 2.0;
    final maxDy = (size.height * (targetScale - 1.0)) / 2.0;
    final targetTranslation = targetScale <= 1.0
        ? Offset.zero
        : Offset(
            _translation.dx.clamp(-maxDx, maxDx),
            _translation.dy.clamp(-maxDy, maxDy),
          );

    _scaleAnimation = Tween<double>(begin: _scale, end: targetScale).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _rotationAnimation = Tween<double>(
      begin: _rotation,
      end: targetRotation,
    ).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _translationAnimation = Tween<Offset>(
      begin: _translation,
      end: targetTranslation,
    ).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );

    _animController.forward(from: 0.0);
  }

  void _onDoubleTapDown(TapDownDetails details) {
    _doubleTapPosition = details.localPosition;
  }

  void _onDoubleTap() {
    if (_animController.isAnimating) return;
    final size = context.size ?? const Size(400, 600);

    final double targetScale;
    if (_scale < 1.8) {
      targetScale = 2.5;
    } else if (_scale < 3.2) {
      targetScale = 4.0;
    } else {
      targetScale = 1.0;
    }

    // Keep the current snapped quadrant
    const quarterTurn = math.pi / 2;
    final targetRotation = (_rotation / quarterTurn).round() * quarterTurn;

    final Offset targetTranslation;
    if (targetScale <= 1.0) {
      targetTranslation = Offset.zero;
    } else {
      final center = Offset(size.width / 2, size.height / 2);
      final delta = center - _doubleTapPosition;
      final maxDx = (size.width * (targetScale - 1.0)) / 2.0;
      final maxDy = (size.height * (targetScale - 1.0)) / 2.0;
      targetTranslation = Offset(
        (delta.dx * (targetScale - 1.0)).clamp(-maxDx, maxDx),
        (delta.dy * (targetScale - 1.0)).clamp(-maxDy, maxDy),
      );
    }

    _scaleAnimation = Tween<double>(begin: _scale, end: targetScale).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOutCubic),
    );
    _rotationAnimation = Tween<double>(
      begin: _rotation,
      end: targetRotation,
    ).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOutCubic),
    );
    _translationAnimation = Tween<Offset>(
      begin: _translation,
      end: targetTranslation,
    ).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOutCubic),
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

    return Hero(
      tag: widget.heroTag,
      child: Material(
        type: MaterialType.transparency,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onScaleEnd: _onScaleEnd,
          onDoubleTapDown: _onDoubleTapDown,
          onDoubleTap: _onDoubleTap,
          child: Center(
            child: Transform.translate(
              offset: _translation,
              child: Transform.rotate(
                angle: _rotation,
                child: Transform.scale(
                  scale: _scale,
                  child: imageWidget,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

