import 'dart:typed_data';
import 'package:flutter/material.dart';

import 'image_viewer.dart';
import 'video_viewer.dart';

export 'video_viewer.dart' show formatMediaDuration, openFloatingVideoWindow;

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
    this.fileName,
  });
  final String id;
  final String messageId;
  final MediaPreviewType type;
  final String source;
  final Object heroTag;
  final Uint8List? bytes;
  final String? thumbnail;
  /// 下载时使用的文件名（可选）。
  final String? fileName;
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
  int _pointerCount = 0;

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
    if (_pointerCount >= 2 || _currentScale > 1.05) return;
    _resetController.stop();
    _isDragging = true;
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_pointerCount >= 2 || _currentScale > 1.05) {
      if (_isDragging) {
        _isDragging = false;
        _dragOffset = Offset.zero;
        setState(() {});
      }
      return;
    }
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

  /// 下载当前媒体（stub — 业务层可替换）。
  void _downloadCurrent() {
    final item = widget.items[_index];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('下载：${item.fileName ?? item.source.split('/').last}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 分享当前媒体（stub — 业务层可替换）。
  void _shareCurrent() {
    final item = widget.items[_index];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('分享：${item.fileName ?? item.source.split('/').last}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final routeAnimation = ModalRoute.of(context)?.animation;
    return AnimatedBuilder(
      animation: routeAnimation ?? const AlwaysStoppedAnimation<double>(1.0),
      builder: (context, _) {
        final routeProgress = routeAnimation?.value ?? 1.0;
        final bgOpacity =
            (_backgroundOpacity * routeProgress).clamp(0.0, 1.0);
        final chromeOpacity =
            ((1.0 - _dragProgress * 3.0) * routeProgress).clamp(0.0, 1.0);

        return Scaffold(
          backgroundColor: Colors.black.withValues(alpha: bgOpacity),
          body: SafeArea(
            child: Listener(
              onPointerDown: (_) => setState(() => _pointerCount++),
              onPointerUp:
                  (_) => setState(() {
                    if (_pointerCount > 0) _pointerCount--;
                  }),
              onPointerCancel:
                  (_) => setState(() {
                    if (_pointerCount > 0) _pointerCount--;
                  }),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  if (_dragOffset == Offset.zero) {
                    setState(() => _chrome = !_chrome);
                  }
                },
                onVerticalDragStart:
                    widget.items[_index].type == MediaPreviewType.video
                        ? _onVerticalDragStart
                        : null,
                onVerticalDragUpdate:
                    widget.items[_index].type == MediaPreviewType.video
                        ? _onVerticalDragUpdate
                        : null,
                onVerticalDragEnd:
                    widget.items[_index].type == MediaPreviewType.video
                        ? _onVerticalDragEnd
                        : null,
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
                              _isDragging ||
                                      _dragOffset != Offset.zero ||
                                      _pointerCount >= 2 ||
                                      _currentScale > 1.05
                                  ? const NeverScrollableScrollPhysics()
                                  : const BouncingScrollPhysics(),
                          itemCount: widget.items.length,
                          onPageChanged:
                              (value) => setState(() {
                                _index = value;
                                _currentScale = 1.0;
                                _dragOffset = Offset.zero;
                              }),
                          itemBuilder: (context, index) {
                            final item = widget.items[index];
                            if (item.type == MediaPreviewType.image) {
                              return ImageViewer(
                                heroTag: item.heroTag,
                                source: item.source,
                                bytes: item.bytes,
                                onScaleChanged: (scale) {
                                  _currentScale = scale;
                                },
                                onDismissProgress: (offset) {
                                  setState(() {
                                    _dragOffset = offset;
                                    _isDragging = offset != Offset.zero;
                                  });
                                },
                                onDismissEnd: () => Navigator.of(context).pop(),
                              );
                            } else {
                              return VideoViewer(
                                item: item,
                                active: index == _index,
                                items: widget.items,
                                initialIndex: index,
                              );
                            }
                          },
                        ),
                      ),
                    ),
                    // ── 关闭按钮（左上）──────────────────────────────
                    if (_chrome && chromeOpacity > 0.0)
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Opacity(
                          opacity: chromeOpacity,
                          child: IconButton(
                            tooltip: '关闭',
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close, color: Colors.white),
                          ),
                        ),
                      ),
                    // ── 页码指示器（底部中央）────────────────────────
                    if (_chrome &&
                        widget.items.length > 1 &&
                        chromeOpacity > 0.0)
                      Positioned(
                        bottom: 18,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
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
                      ),
                    // ── 下载 / 分享（右下角）─────────────────────────
                    if (_chrome && chromeOpacity > 0.0)
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Opacity(
                          opacity: chromeOpacity,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _ChromeButton(
                                tooltip: '下载',
                                icon: Icons.download_rounded,
                                onPressed: _downloadCurrent,
                              ),
                              const SizedBox(width: 4),
                              _ChromeButton(
                                tooltip: '分享',
                                icon: Icons.share_rounded,
                                onPressed: _shareCurrent,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 半透明圆形背景按钮，用于预览页 chrome 区域。
class _ChromeButton extends StatelessWidget {
  const _ChromeButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.45),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}
