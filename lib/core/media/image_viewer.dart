import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';

import '../widgets/app_toast.dart';
import 'image_provider_factory.dart';

/// Professional image viewer with two-finger scale & twist rotation (with automatic
/// 90-degree quadrant magnetic snapping, like system photo albums), focal double-tap
/// zoom, single-finger dismiss drag delegation, and comprehensive gesture trace logging.
class ImageViewer extends StatefulWidget {
  const ImageViewer({
    this.heroTag,
    required this.source,
    this.bytes,
    this.thumbnail,
    this.thumbnailBytes,
    this.onScaleChanged,
    this.onDismissProgress,
    this.onDismissEnd,
    this.scaleSensitivity = 1.0,
    this.rotationSensitivity = 1.0,
    this.minScale = 1.0,
    this.maxScale = 5.0,
    this.enableLogs = true,
    super.key,
  });

  final Object? heroTag;
  final String source;
  final Uint8List? bytes;
  final String? thumbnail;
  final Uint8List? thumbnailBytes;
  final ValueChanged<double>? onScaleChanged;
  final ValueChanged<Offset>? onDismissProgress;
  final VoidCallback? onDismissEnd;

  /// Sensitivity factor for two-finger distance zoom (default 1.0).
  final double scaleSensitivity;

  /// Sensitivity factor for two-finger twist rotation (default 1.0).
  final double rotationSensitivity;

  /// Minimum stable scale after release (default 1.0).
  final double minScale;

  /// Maximum stable scale after release (default 5.0).
  final double maxScale;

  /// Whether to print verbose [ImageGestureTrace] debug logs.
  final bool enableLogs;

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
  bool _isDismissDragging = false;
  bool _hasShownErrorToast = false;

  String? _effectiveThumbnailUrl;
  Uint8List? _effectiveThumbnailBytes;

  late final AnimationController _animController;
  Animation<double>? _scaleAnimation;
  Animation<double>? _rotationAnimation;
  Animation<Offset>? _translationAnimation;

  void _log(String message) {
    if (widget.enableLogs) {
      debugPrint('[ImageGestureTrace] $message');
    }
  }

  @override
  void initState() {
    super.initState();
    _effectiveThumbnailBytes = widget.thumbnailBytes;
    if (widget.thumbnail != null && widget.thumbnail!.isNotEmpty) {
      _effectiveThumbnailUrl = widget.thumbnail;
    } else if (widget.thumbnailBytes == null && widget.bytes == null) {
      _effectiveThumbnailUrl = widget.source;
    }

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
  void didUpdateWidget(ImageViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.thumbnailBytes != null) {
      _effectiveThumbnailBytes = widget.thumbnailBytes;
    }
    if (widget.thumbnail != null && widget.thumbnail!.isNotEmpty) {
      _effectiveThumbnailUrl = widget.thumbnail;
    } else if (widget.source != oldWidget.source &&
        oldWidget.source.isNotEmpty) {
      // Retain previously rendered source as thumbnail base during transition
      _effectiveThumbnailUrl ??= oldWidget.source;
    }
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
    _isDismissDragging = false;
    _log('🟢 [ScaleStart] focalPoint=${details.localFocalPoint} baseScale=${_baseScale.toStringAsFixed(2)} baseRot=${(_baseRotation * 180 / math.pi).toStringAsFixed(1)}°');
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final count = details.pointerCount;
    final hasScaleChange = (details.scale - 1.0).abs() > 0.005;
    final hasRotationChange = details.rotation.abs() > 0.005;
    final isMultiTouch = count >= 2 || hasScaleChange || hasRotationChange;

    if (isMultiTouch) {
      // Multi-touch mode: pinch distance zoom & twist rotation
      if (_isDismissDragging) {
        _isDismissDragging = false;
        widget.onDismissProgress?.call(Offset.zero);
      }

      final effectiveScaleDelta = (details.scale - 1.0) * widget.scaleSensitivity;
      final rawScale = _baseScale * (1.0 + effectiveScaleDelta);
      _scale = rawScale.clamp(0.5, 7.0);

      final effectiveRotation = details.rotation * widget.rotationSensitivity;
      _rotation = _baseRotation + effectiveRotation;

      _translation = _baseTranslation + details.focalPointDelta;
      _log('🔄 [MultiTouch] pointers=$count scale=${_scale.toStringAsFixed(2)} rot=${(_rotation * 180 / math.pi).toStringAsFixed(1)}° dx=${_translation.dx.toStringAsFixed(1)} dy=${_translation.dy.toStringAsFixed(1)}');
      widget.onScaleChanged?.call(_scale);
      setState(() {});
    } else if (_scale > 1.05) {
      // Zoomed-in pan mode
      _translation += details.focalPointDelta;
      _log('👆 [Pan] translation=$_translation scale=${_scale.toStringAsFixed(2)}');
      setState(() {});
    } else {
      // Single finger at 1.0 scale: vertical dismiss drag
      if (details.focalPointDelta.dy != 0 || _isDismissDragging) {
        _isDismissDragging = true;
        _translation += Offset(details.focalPointDelta.dx * 0.7, details.focalPointDelta.dy);
        _log('👇 [DismissDrag] dy=${_translation.dy.toStringAsFixed(1)}');
        widget.onDismissProgress?.call(_translation);
        setState(() {});
      }
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _log('🔴 [ScaleEnd] scale=${_scale.toStringAsFixed(2)} rot=${(_rotation * 180 / math.pi).toStringAsFixed(1)}° translation=$_translation dismissDrag=$_isDismissDragging');
    final size = context.size ?? const Size(400, 600);

    if (_isDismissDragging) {
      final velocity = details.velocity.pixelsPerSecond.dy.abs();
      final distance = _translation.dy.abs();
      final shouldClose = distance > 80.0 || velocity > 500.0;
      if (shouldClose) {
        _log('🚪 [Dismiss] Trigger close velocity=$velocity distance=$distance');
        widget.onDismissEnd?.call();
        return;
      }

      // Reset dismiss drag offset
      _isDismissDragging = false;
      widget.onDismissProgress?.call(Offset.zero);
    }

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

    _log('⚡ [DoubleTap] targetScale=$targetScale atPos=$_doubleTapPosition');

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

  Widget _buildThumbnailWidget({double opacity = 1.0}) {
    Widget child = const SizedBox.shrink();
    if (_effectiveThumbnailBytes != null) {
      child = Image.memory(
        _effectiveThumbnailBytes!,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.contain,
        gaplessPlayback: true,
      );
    } else {
      final thumb = _effectiveThumbnailUrl;
      if (thumb != null && thumb.isNotEmpty) {
        child = Image(
          image: createImageProvider(thumb),
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        );
      }
    }

    return AnimatedOpacity(
      opacity: opacity,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: child,
    );
  }

  Widget _buildErrorWidget(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  ) {
    if (!_hasShownErrorToast) {
      _hasShownErrorToast = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showToast('图片加载失败', type: ToastType.error);
      });
    }
    return const Column(
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasThumbnail = _effectiveThumbnailBytes != null ||
        (_effectiveThumbnailUrl != null &&
            _effectiveThumbnailUrl!.isNotEmpty &&
            (_effectiveThumbnailUrl != widget.source || widget.bytes != null));

    Widget highResWidget;
    if (widget.bytes != null) {
      highResWidget = Image.memory(
        widget.bytes!,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (!hasThumbnail) return child;
          final isLoaded = wasSynchronouslyLoaded || frame != null;
          return Stack(
            fit: StackFit.passthrough,
            alignment: Alignment.center,
            children: <Widget>[
              _buildThumbnailWidget(opacity: isLoaded ? 0.0 : 1.0),
              AnimatedOpacity(
                opacity: isLoaded ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                child: child,
              ),
            ],
          );
        },
        errorBuilder: _buildErrorWidget,
      );
    } else {
      highResWidget = Image(
        image: createImageProvider(widget.source),
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (!hasThumbnail) return child;
          final isLoaded = wasSynchronouslyLoaded || frame != null;
          return Stack(
            fit: StackFit.passthrough,
            alignment: Alignment.center,
            children: <Widget>[
              _buildThumbnailWidget(opacity: isLoaded ? 0.0 : 1.0),
              AnimatedOpacity(
                opacity: isLoaded ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                child: child,
              ),
            ],
          );
        },
        errorBuilder: _buildErrorWidget,
      );
    }

    final Widget imageWidget = highResWidget;

    Widget content = Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        onDoubleTapDown: _onDoubleTapDown,
        onDoubleTap: _onDoubleTap,
        child: Container(
          color: Colors.transparent,
          width: double.infinity,
          height: double.infinity,
          alignment: Alignment.center,
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
    );

    if (widget.heroTag != null) {
      content = Hero(
        tag: widget.heroTag!,
        child: content,
      );
    }
    return content;
  }
}


