import 'package:flutter/material.dart';

enum FloatingWindowType {
  video,
  videoCall,
  audioCall,
  webView,
  transfer,
  map,
  camera,
  custom,
}

enum FloatingWindowContentMode { flutter, platformView }

@immutable
class FloatingWindowOptions {
  const FloatingWindowOptions({
    this.draggable = true,
    this.snapToEdge = true,
    this.resizable = false,
    this.keepAspectRatio = false,
    this.avoidKeyboard = true,
    this.avoidSafeArea = true,
    this.margin = const EdgeInsets.all(12),
    this.initialSize = const Size(180, 120),
    this.minSize = const Size(120, 72),
    this.maxSize,
    this.initialPosition,
    this.snapDuration = const Duration(milliseconds: 180),
  });

  factory FloatingWindowOptions.video() => const FloatingWindowOptions(
    keepAspectRatio: true,
    initialSize: Size(180, 102),
    minSize: Size(128, 72),
  );

  factory FloatingWindowOptions.custom() => const FloatingWindowOptions();

  final bool draggable;
  final bool snapToEdge;
  final bool resizable;
  final bool keepAspectRatio;
  final bool avoidKeyboard;
  final bool avoidSafeArea;
  final EdgeInsets margin;
  final Size initialSize;
  final Size minSize;
  final Size? maxSize;
  final Offset? initialPosition;
  final Duration snapDuration;
}

@immutable
class FloatingWindowEntry {
  const FloatingWindowEntry({
    required this.id,
    required this.type,
    required this.contentMode,
    required this.child,
    required this.options,
    required this.position,
    required this.size,
    required this.visible,
    required this.zIndex,
    this.onRestore,
  });

  final String id;
  final FloatingWindowType type;
  final FloatingWindowContentMode contentMode;
  final Widget child;
  final FloatingWindowOptions options;
  final Offset position;
  final Size size;
  final bool visible;
  final int zIndex;

  /// Restores this floating item to its primary presentation, if supported.
  final VoidCallback? onRestore;

  FloatingWindowEntry copyWith({
    Widget? child,
    FloatingWindowOptions? options,
    Offset? position,
    Size? size,
    bool? visible,
    int? zIndex,
    VoidCallback? onRestore,
  }) => FloatingWindowEntry(
    id: id,
    type: type,
    contentMode: contentMode,
    child: child ?? this.child,
    options: options ?? this.options,
    position: position ?? this.position,
    size: size ?? this.size,
    visible: visible ?? this.visible,
    zIndex: zIndex ?? this.zIndex,
    onRestore: onRestore ?? this.onRestore,
  );
}

@immutable
class FloatingWindowBounds {
  const FloatingWindowBounds(this.rect);
  final Rect rect;

  Offset clampPosition(Offset position, Size size) => Offset(
    position.dx.clamp(rect.left, rect.right - size.width),
    position.dy.clamp(rect.top, rect.bottom - size.height),
  );

  Size clampSize(Size size, FloatingWindowOptions options) {
    final max = options.maxSize ?? rect.size;
    var width = size.width.clamp(options.minSize.width, max.width).toDouble();
    var height =
        size.height.clamp(options.minSize.height, max.height).toDouble();
    width = width.clamp(options.minSize.width, rect.width).toDouble();
    height = height.clamp(options.minSize.height, rect.height).toDouble();
    if (options.keepAspectRatio && size.height > 0) {
      final ratio = size.width / size.height;
      height =
          (width / ratio).clamp(options.minSize.height, rect.height).toDouble();
    }
    return Size(width, height);
  }
}
