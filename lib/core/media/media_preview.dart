import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../floating_window/floating_window.dart';
import 'video_playback_session.dart';

enum MediaPreviewType { image, video }

@immutable
class MediaPreviewItem {
  const MediaPreviewItem({
    required this.id,
    required this.messageId,
    required this.type,
    required this.source,
    required this.heroTag,
    this.bytes,
    this.thumbnail,
  });
  final String id;
  final String messageId;
  final MediaPreviewType type;
  final String source;
  final Object heroTag;
  final Uint8List? bytes;
  final String? thumbnail;
}

String buildMediaHeroTag({
  required String messageId,
  required String mediaId,
}) => 'chat-media-$messageId-$mediaId';

abstract class MediaPreview {
  static Future<void> open(
    BuildContext context, {
    required List<MediaPreviewItem> items,
    int initialIndex = 0,
  }) {
    if (items.isEmpty) return Future.value();
    final safeInitialIndex = initialIndex.clamp(0, items.length - 1);
    return openWithNavigator(
      Navigator.of(context),
      items: items,
      initialIndex: safeInitialIndex,
    );
  }

  static Future<void> openWithNavigator(
    NavigatorState navigator, {
    required List<MediaPreviewItem> items,
    int initialIndex = 0,
  }) {
    if (items.isEmpty) return Future.value();
    final safeInitialIndex = initialIndex.clamp(0, items.length - 1);
    return navigator.push<void>(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 240),
        reverseTransitionDuration: const Duration(milliseconds: 240),
        pageBuilder:
            (_, animation, secondaryAnimation) =>
                _MediaPreviewPage(items: items, initialIndex: safeInitialIndex),
      ),
    );
  }
}

class _MediaPreviewPage extends StatefulWidget {
  const _MediaPreviewPage({required this.items, required this.initialIndex});
  final List<MediaPreviewItem> items;
  final int initialIndex;
  @override
  State<_MediaPreviewPage> createState() => _MediaPreviewPageState();
}

class _MediaPreviewPageState extends State<_MediaPreviewPage>
    with SingleTickerProviderStateMixin {
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;
  bool _chrome = true;
  Offset _dragOffset = Offset.zero;
  bool _isDragging = false;
  double _currentScale = 1.0;

  late final AnimationController _resetController;
  Animation<Offset>? _resetAnimation;

  @override
  void initState() {
    super.initState();
    _resetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        if (_resetAnimation != null) {
          setState(() {
            _dragOffset = _resetAnimation!.value;
          });
        }
      });
  }

  @override
  void dispose() {
    _resetController.dispose();
    _pages.dispose();
    super.dispose();
  }

  double get _dragProgress =>
      (_dragOffset.dy.abs() / 280.0).clamp(0.0, 1.0);

  double get _backgroundOpacity =>
      (1.0 - _dragProgress * 0.95).clamp(0.0, 1.0);

  double get _mediaScale => (1.0 - _dragProgress * 0.35).clamp(0.65, 1.0);

  void _onVerticalDragStart(DragStartDetails details) {
    if (_currentScale > 1.05) return;
    _resetController.stop();
    _isDragging = true;
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_currentScale > 1.05) return;
    _isDragging = true;
    setState(() {
      final newDy = _dragOffset.dy + details.delta.dy;
      final newDx = _dragOffset.dx + details.delta.dx;
      _dragOffset = Offset(newDx, newDy);
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_currentScale > 1.05) return;
    _isDragging = false;
    final velocity = (details.primaryVelocity ?? 0.0).abs();
    final distance = _dragOffset.dy.abs();
    final shouldClose = distance > 80.0 || velocity > 500.0;
    if (shouldClose) {
      Navigator.of(context).pop();
    } else {
      _resetAnimation = Tween<Offset>(
        begin: _dragOffset,
        end: Offset.zero,
      ).animate(
        CurvedAnimation(
          parent: _resetController,
          curve: Curves.easeOutCubic,
        ),
      );
      _resetController.forward(from: 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgOpacity = _backgroundOpacity;
    final chromeOpacity = (1.0 - _dragProgress * 3.0).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: bgOpacity),
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            if (_dragOffset == Offset.zero) {
              setState(() => _chrome = !_chrome);
            }
          },
          onVerticalDragStart: _onVerticalDragStart,
          onVerticalDragUpdate: _onVerticalDragUpdate,
          onVerticalDragEnd: _onVerticalDragEnd,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Transform.translate(
                offset: _dragOffset,
                child: Transform.scale(
                  scale: _mediaScale,
                  child: PageView.builder(
                    controller: _pages,
                    physics:
                        _isDragging || _dragOffset != Offset.zero
                            ? const NeverScrollableScrollPhysics()
                            : const BouncingScrollPhysics(),
                    itemCount: widget.items.length,
                    onPageChanged: (value) => setState(() => _index = value),
                    itemBuilder:
                        (_, index) => Center(
                          child:
                              widget.items[index].type == MediaPreviewType.image
                                  ? _Image(
                                    item: widget.items[index],
                                    onScaleChanged: (scale) {
                                      _currentScale = scale;
                                    },
                                  )
                                  : _Video(
                                    item: widget.items[index],
                                    active: index == _index,
                                    items: widget.items,
                                    initialIndex: index,
                                  ),
                        ),
                  ),
                ),
              ),
              if (_chrome && chromeOpacity > 0.0)
                Positioned(
                  top: 4,
                  left: 4,
                  child: Opacity(
                    opacity: chromeOpacity,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ),
                ),
              if (_chrome && widget.items.length > 1 && chromeOpacity > 0.0)
                Positioned(
                  bottom: 18,
                  left: 0,
                  right: 0,
                  child: Opacity(
                    opacity: chromeOpacity,
                    child: Text(
                      '${_index + 1} / ${widget.items.length}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        shadows: [
                          Shadow(blurRadius: 4, color: Colors.black54),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Image extends StatefulWidget {
  const _Image({required this.item, this.onScaleChanged});
  final MediaPreviewItem item;
  final ValueChanged<double>? onScaleChanged;

  @override
  State<_Image> createState() => _ImageState();
}

class _ImageState extends State<_Image> {
  final TransformationController _transformController =
      TransformationController();

  @override
  void initState() {
    super.initState();
    _transformController.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transformController.removeListener(_onTransformChanged);
    _transformController.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final scale = _transformController.value.getMaxScaleOnAxis();
    widget.onScaleChanged?.call(scale);
  }

  void _onDoubleTap() {
    if (_transformController.value.getMaxScaleOnAxis() > 1.05) {
      _transformController.value = Matrix4.identity();
    } else {
      _transformController.value = Matrix4.identity()..scale(2.5);
    }
  }

  @override
  Widget build(BuildContext context) {
    final image =
        widget.item.bytes != null
            ? Image.memory(widget.item.bytes!, fit: BoxFit.contain)
            : Image.network(
              widget.item.source,
              fit: BoxFit.contain,
              errorBuilder:
                  (_, _, _) => const Icon(
                    Icons.broken_image,
                    color: Colors.white,
                    size: 48,
                  ),
            );
    return Hero(
      tag: widget.item.heroTag,
      child: GestureDetector(
        onDoubleTap: _onDoubleTap,
        child: InteractiveViewer(
          transformationController: _transformController,
          minScale: 1.0,
          maxScale: 5.0,
          child: Center(child: image),
        ),
      ),
    );
  }
}

class _Video extends StatefulWidget {
  const _Video({
    required this.item,
    required this.active,
    required this.items,
    required this.initialIndex,
  });
  final MediaPreviewItem item;
  final bool active;
  final List<MediaPreviewItem> items;
  final int initialIndex;
  @override
  State<_Video> createState() => _VideoState();
}

class _VideoState extends State<_Video> {
  late final VideoPlaybackSession _session;
  bool _handedOff = false;
  bool _handoffPending = false;

  @override
  void initState() {
    super.initState();
    _session = VideoPlaybackSessionRegistry.obtain(
      _sessionId,
      widget.item.source,
    )..initialize();
    _session.addListener(_onSessionChanged);
  }

  @override
  void didUpdateWidget(_Video old) {
    super.didUpdateWidget(old);
    if (!widget.active) _session.controller?.pause();
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  void _minimize() {
    if (_handoffPending || _handedOff) return;
    final manager = FloatingWindowScope.of(context);
    final id = _sessionId;
    final navigator = Navigator.of(context);
    // A single Android video texture cannot be mounted by both the fullscreen
    // route and the floating window at the same time. Remove this host first,
    // then attach the retained session to the floating window on the next
    // frame.
    setState(() => _handoffPending = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _handedOff = true;
      void restoreToFullscreen() {
        manager.close(id);
        MediaPreview.openWithNavigator(
          navigator,
          items: widget.items,
          initialIndex: widget.initialIndex,
        );
      }

      manager.show(
        id: id,
        type: FloatingWindowType.video,
        options: FloatingWindowOptions.video(),
        onRestore: restoreToFullscreen,
        child: _FloatingVideoContent(
          session: _session,
          label: widget.item.id,
          onClose: () {
            VideoPlaybackSessionRegistry.release(id, _session);
            manager.close(id);
          },
          onRestore: restoreToFullscreen,
        ),
      );
      navigator.pop();
    });
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    if (!_handedOff) {
      VideoPlaybackSessionRegistry.release(_sessionId, _session);
    }
    super.dispose();
  }

  String get _sessionId => 'video:${widget.item.messageId}:${widget.item.id}';

  @override
  Widget build(BuildContext context) {
    if (_handoffPending) return const SizedBox.shrink();
    if (_session.error != null) {
      return Text(
        '视频加载失败：${_session.error}',
        style: const TextStyle(color: Colors.white),
      );
    }
    final controller = _session.controller;
    if (controller == null || !controller.value.isInitialized) {
      return const CircularProgressIndicator(color: Colors.white);
    }
    return Hero(
      tag: widget.item.heroTag,
      child: Stack(
        alignment: Alignment.center,
        children: [
          GestureDetector(
            onTap: _session.togglePlayback,
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  VideoPlayer(controller),
                  if (!controller.value.isPlaying)
                    const Icon(
                      Icons.play_circle_fill,
                      color: Colors.white,
                      size: 64,
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 8,
            top: 8,
            child: IconButton(
              tooltip: '缩小为浮窗',
              onPressed: _minimize,
              icon: const Icon(
                Icons.picture_in_picture_alt,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingVideoContent extends StatefulWidget {
  const _FloatingVideoContent({
    required this.session,
    required this.label,
    required this.onClose,
    required this.onRestore,
  });
  final VideoPlaybackSession session;
  final String label;
  final VoidCallback onClose;
  final VoidCallback onRestore;

  @override
  State<_FloatingVideoContent> createState() => _FloatingVideoContentState();
}

class _FloatingVideoContentState extends State<_FloatingVideoContent> {
  @override
  void initState() {
    super.initState();
    widget.session.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.session.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.session.controller;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.session.togglePlayback,
          child: Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),
        ),
        Center(
          child: IconButton.filledTonal(
            tooltip: controller.value.isPlaying ? '暂停播放' : '播放视频',
            onPressed: widget.session.togglePlayback,
            icon: Icon(
              controller.value.isPlaying
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_fill,
              size: 42,
            ),
          ),
        ),
        Positioned(
          left: 2,
          top: 2,
          child: IconButton(
            tooltip: '恢复全屏播放',
            onPressed: widget.onRestore,
            icon: const Icon(Icons.fullscreen, color: Colors.white),
          ),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: IconButton(
            tooltip: '关闭视频',
            onPressed: widget.onClose,
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ),
      ],
    );
  }
}
