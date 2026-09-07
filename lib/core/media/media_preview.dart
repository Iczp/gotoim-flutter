import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/app_navigation.dart';
import '../services/media/media_gallery_saver.dart';
import '../widgets/app_toast.dart';
import 'image_provider_factory.dart';
import 'image_viewer.dart';
import 'media_downloader.dart';
import 'video_viewer.dart';

export 'media_downloader.dart';
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
    this.localPath,
    this.createdAt,
    this.userId,
    this.chatTarget,
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
  /// 本地已下载文件缓存路径（可选）。
  final String? localPath;
  /// 消息创建日期（用于按日期分类保存附件到 `LocalShare/聊天文件/<用户>/<聊天对象>/<分类>/<yyyy-MM-dd>`）。
  final DateTime? createdAt;
  /// 用户 ID（支持多账号切换隔离）。
  final String? userId;
  /// 聊天对象会话 ID 或名称。
  final String? chatTarget;

  MediaPreviewItem copyWith({
    String? id,
    String? messageId,
    MediaPreviewType? type,
    String? source,
    Object? heroTag,
    Uint8List? bytes,
    String? thumbnail,
    String? fileName,
    String? localPath,
    DateTime? createdAt,
    String? userId,
    String? chatTarget,
  }) =>
      MediaPreviewItem(
        id: id ?? this.id,
        messageId: messageId ?? this.messageId,
        type: type ?? this.type,
        source: source ?? this.source,
        heroTag: heroTag ?? this.heroTag,
        bytes: bytes ?? this.bytes,
        thumbnail: thumbnail ?? this.thumbnail,
        fileName: fileName ?? this.fileName,
        localPath: localPath ?? this.localPath,
        createdAt: createdAt ?? this.createdAt,
        userId: userId ?? this.userId,
        chatTarget: chatTarget ?? this.chatTarget,
      );
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
    MediaDownloader? downloader,
  }) {
    if (items.isEmpty) return Future.value();
    final safeInitialIndex = initialIndex.clamp(0, items.length - 1);
    final nav = Navigator.maybeOf(context, rootNavigator: true) ??
        Navigator.maybeOf(context) ??
        rootNavigatorKey.currentState;
    if (nav == null) return Future.value();
    return openWithNavigator(
      nav,
      items: items,
      initialIndex: safeInitialIndex,
      downloader: downloader,
    );
  }

  static Future<void> openWithNavigator(
    NavigatorState navigator, {
    required List<MediaPreviewItem> items,
    int initialIndex = 0,
    MediaDownloader? downloader,
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
                _MediaPreviewPage(
                  items: items,
                  initialIndex: safeInitialIndex,
                  downloader: downloader ?? DefaultMediaDownloader.instance,
                ),
      ),
    );
  }
}

class _MediaPreviewPage extends StatefulWidget {
  const _MediaPreviewPage({
    required this.items,
    required this.initialIndex,
    required this.downloader,
  });
  final List<MediaPreviewItem> items;
  final int initialIndex;
  final MediaDownloader downloader;
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

  /// 下载/复制当前媒体到系统相册。
  Future<void> _downloadCurrent() async {
    final item = widget.items[_index];
    try {
      final cached = await widget.downloader.getCachedPath(item);
      if (cached != null) {
        // 已经下载 -> 复制到相册
        if (item.type == MediaPreviewType.image) {
          await MediaGallerySaver.saveImage(cached);
          showToast('已复制到系统相册', type: ToastType.success);
        } else if (item.type == MediaPreviewType.video) {
          await MediaGallerySaver.saveVideo(cached);
          showToast('已复制到系统相册', type: ToastType.success);
        } else {
          showToast('已保存在本地', type: ToastType.info);
        }
      } else {
        // 未下载 -> 下载到相册
        showToast('正在下载媒体文件...', type: ToastType.info);
        final path = await widget.downloader.download(item);
        if (path.isNotEmpty) {
          if (item.type == MediaPreviewType.image) {
            await MediaGallerySaver.saveImage(path);
            showToast('已下载并保存到相册', type: ToastType.success);
          } else if (item.type == MediaPreviewType.video) {
            await MediaGallerySaver.saveVideo(path);
            showToast('已下载并保存到相册', type: ToastType.success);
          } else {
            showToast('下载完成', type: ToastType.success);
          }
        }
      }
    } catch (e) {
      showToast('保存相册失败：$e', type: ToastType.error);
    }
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

  /// 将当前播放的视频缩小为画中画悬浮窗（与顶部关闭按钮平级）。
  void _minimizeCurrentVideo() {
    final item = widget.items[_index];
    if (item.type != MediaPreviewType.video) return;
    openFloatingVideoWindow(
      context,
      item: item,
      items: widget.items,
      initialIndex: _index,
    );
    Navigator.of(context).pop();
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
                            return _MediaPreviewItemView(
                              item: item,
                              active: index == _index,
                              items: widget.items,
                              index: index,
                              downloader: widget.downloader,
                              isDragging: _isDragging || _dragOffset != Offset.zero,
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
                    // ── 浮动小窗口按钮（右上，与关闭按钮平级，手指滑动时小窗口按钮不移动）──
                    if (_chrome &&
                        chromeOpacity > 0.0 &&
                        widget.items[_index].type == MediaPreviewType.video)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Opacity(
                          opacity: chromeOpacity,
                          child: IconButton(
                            tooltip: '缩小为浮窗',
                            onPressed: _minimizeCurrentVideo,
                            icon: const Icon(
                              Icons.picture_in_picture_alt,
                              color: Colors.white,
                            ),
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

class _MediaPreviewItemView extends StatefulWidget {
  const _MediaPreviewItemView({
    required this.item,
    required this.active,
    required this.items,
    required this.index,
    required this.downloader,
    required this.onScaleChanged,
    required this.onDismissProgress,
    required this.onDismissEnd,
    this.isDragging = false,
  });

  final MediaPreviewItem item;
  final bool active;
  final List<MediaPreviewItem> items;
  final int index;
  final MediaDownloader downloader;
  final ValueChanged<double> onScaleChanged;
  final ValueChanged<Offset> onDismissProgress;
  final VoidCallback onDismissEnd;
  final bool isDragging;

  @override
  State<_MediaPreviewItemView> createState() => _MediaPreviewItemViewState();
}

class _MediaPreviewItemViewState extends State<_MediaPreviewItemView>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  String? _localPath;
  bool _isReady = false;
  bool _isDownloading = false;
  double _progress = 0.0;
  Object? _error;

  bool _fileExists(String? path) {
    if (path == null || path.isEmpty) return false;
    if (kIsWeb) return true;
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.item.localPath != null &&
        widget.item.localPath!.isNotEmpty &&
        _fileExists(widget.item.localPath)) {
      _localPath = widget.item.localPath;
      _isReady = true;
    } else if (widget.item.bytes != null &&
        widget.item.type == MediaPreviewType.image) {
      _isReady = true;
    } else {
      _checkStatus();
    }
  }

  @override
  void didUpdateWidget(_MediaPreviewItemView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.item.source != oldWidget.item.source ||
        widget.item.id != oldWidget.item.id) {
      _checkStatus();
    } else if (widget.active && !_isReady && !_isDownloading && _error == null) {
      _startDownload();
    }
  }

  Future<void> _checkStatus() async {
    if (widget.item.localPath != null &&
        widget.item.localPath!.isNotEmpty &&
        _fileExists(widget.item.localPath)) {
      if (mounted) {
        setState(() {
          _localPath = widget.item.localPath;
          _isReady = true;
        });
      }
      return;
    }
    if (widget.item.bytes != null &&
        widget.item.type == MediaPreviewType.image) {
      if (mounted) {
        setState(() {
          _isReady = true;
        });
      }
      return;
    }

    final cached = await widget.downloader.getCachedPath(widget.item);
    if (!mounted) return;
    if (cached != null && _fileExists(cached)) {
      setState(() {
        _localPath = cached;
        _isReady = true;
      });
    } else {
      _startDownload();
    }
  }

  void _startDownload() {
    if (_isDownloading) return;
    final source = widget.item.source;
    if (source.isEmpty ||
        (!source.startsWith('http://') && !source.startsWith('https://'))) {
      setState(() {
        _error = '文件不存在或已被清理';
      });
      showToast('媒体文件不存在或已被清理', type: ToastType.error);
      return;
    }
    setState(() {
      _isDownloading = true;
      _error = null;
      _progress = 0.0;
    });

    widget.downloader.download(
      widget.item,
      onProgress: (received, total) {
        if (!mounted) return;
        setState(() {
          _progress = total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;
        });
      },
    ).then((path) {
      if (!mounted) return;
      setState(() {
        _localPath = path;
        _isDownloading = false;
        _isReady = true;
      });
    }).catchError((Object err) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _error = err;
      });
      showToast('下载媒体失败: $err', type: ToastType.error);
    });
  }

  Widget _buildThumbnail() {
    if (widget.item.bytes != null) {
      return Image.memory(widget.item.bytes!, fit: BoxFit.contain);
    }
    final thumb = widget.item.thumbnail;
    final source =
        (thumb != null && thumb.isNotEmpty) ? thumb : widget.item.source;
    if (source.isNotEmpty) {
      return Image(
        image: createImageProvider(source),
        fit: BoxFit.contain,
        errorBuilder:
            (_, _, _) => const Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 48,
              ),
            ),
      );
    }
    return const Center(
      child: Icon(Icons.image_outlined, color: Colors.white54, size: 48),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Hero(
      tag: widget.item.heroTag,
      child: Material(
        type: MaterialType.transparency,
        child:
            _isReady
                ? (widget.item.type == MediaPreviewType.image
                    ? ImageViewer(
                      heroTag: null,
                      source: _localPath ?? widget.item.source,
                      bytes: widget.item.bytes,
                      thumbnail: widget.item.thumbnail,
                      thumbnailBytes: widget.item.bytes,
                      onScaleChanged: widget.onScaleChanged,
                      onDismissProgress: widget.onDismissProgress,
                      onDismissEnd: widget.onDismissEnd,
                    )
                    : VideoViewer(
                      heroTag: null,
                      item: widget.item.copyWith(
                        source: _localPath ?? widget.item.source,
                      ),
                      active: widget.active,
                      items: widget.items,
                      initialIndex: widget.index,
                      isDragging: widget.isDragging,
                    ))
                : Stack(
                  fit: StackFit.expand,
                  alignment: Alignment.center,
                  children: [
                    _buildThumbnail(),
                    if (widget.item.type == MediaPreviewType.video &&
                        !_isDownloading &&
                        _error == null)
                      const Center(
                        child: Icon(
                          Icons.play_circle_fill_rounded,
                          color: Colors.white70,
                          size: 64,
                        ),
                      ),
                    if (_isDownloading && !_isReady)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox.square(
                                dimension: 40,
                                child: CircularProgressIndicator(
                                  value: _progress > 0 ? _progress : null,
                                  color: Colors.white,
                                  backgroundColor: Colors.white24,
                                  strokeWidth: 3.2,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '${(_progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_error != null)
                      Center(
                        child: GestureDetector(
                          onTap: _startDownload,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.72),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.refresh_rounded,
                                  color: Colors.white,
                                  size: 30,
                                ),
                                SizedBox(height: 6),
                                Text(
                                  '下载失败，点击重试',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
      ),
    );
  }
}

