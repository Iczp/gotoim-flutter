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
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder:
            (_) =>
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

class _MediaPreviewPageState extends State<_MediaPreviewPage> {
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;
  bool _chrome = true;
  double _dragOffset = 0;
  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backgroundOpacity = (1 - _dragOffset / 300).clamp(0.4, 1.0);
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: backgroundOpacity),
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => setState(() => _chrome = !_chrome),
          onVerticalDragUpdate: (details) {
            if (details.delta.dy > 0) {
              setState(() => _dragOffset += details.delta.dy);
            }
          },
          onVerticalDragEnd: (details) {
            final shouldClose =
                _dragOffset > 120 || (details.primaryVelocity ?? 0) > 800;
            if (shouldClose) {
              Navigator.of(context).pop();
            } else {
              setState(() => _dragOffset = 0);
            }
          },
          child: Stack(
            children: [
              Transform.translate(
                offset: Offset(0, _dragOffset),
                child: PageView.builder(
                  controller: _pages,
                  itemCount: widget.items.length,
                  onPageChanged: (value) => setState(() => _index = value),
                  itemBuilder:
                      (_, index) => Center(
                        child:
                            widget.items[index].type == MediaPreviewType.image
                                ? _Image(item: widget.items[index])
                                : _Video(
                                  item: widget.items[index],
                                  active: index == _index,
                                  items: widget.items,
                                  initialIndex: index,
                                ),
                      ),
                ),
              ),
              if (_chrome)
                Positioned(
                  top: 4,
                  left: 4,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ),
              if (_chrome && widget.items.length > 1)
                Positioned(
                  bottom: 18,
                  left: 0,
                  right: 0,
                  child: Text(
                    '${_index + 1} / ${widget.items.length}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Image extends StatelessWidget {
  const _Image({required this.item});
  final MediaPreviewItem item;
  @override
  Widget build(BuildContext context) {
    final image =
        item.bytes != null
            ? Image.memory(item.bytes!, fit: BoxFit.contain)
            : Image.network(
              item.source,
              fit: BoxFit.contain,
              errorBuilder:
                  (_, _, _) => const Icon(
                    Icons.broken_image,
                    color: Colors.white,
                    size: 48,
                  ),
            );
    return Hero(
      tag: item.heroTag,
      child: InteractiveViewer(
        minScale: 1,
        maxScale: 5,
        child: Center(child: image),
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
      manager.show(
        id: id,
        type: FloatingWindowType.video,
        options: FloatingWindowOptions.video(),
        child: _FloatingVideoContent(
          session: _session,
          label: widget.item.id,
          onClose: () {
            VideoPlaybackSessionRegistry.release(id, _session);
            manager.close(id);
          },
          onRestore: () {
            manager.close(id);
            MediaPreview.openWithNavigator(
              navigator,
              items: widget.items,
              initialIndex: widget.initialIndex,
            );
          },
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
          onTap: widget.onRestore,
          child: VideoPlayer(controller),
        ),
        if (!controller.value.isPlaying)
          const Center(
            child: Icon(Icons.play_circle_fill, color: Colors.white, size: 44),
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
