import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:video_player/video_player.dart';

import '../../app/app_navigation.dart';
import '../floating_window/floating_window.dart';
import '../widgets/app_toast.dart';
import 'image_provider_factory.dart';
import 'media_preview.dart';
import 'video_playback_session.dart';

/// 格式化媒体时长（例如 00:15 或 01:23:45）。
String formatMediaDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

String _formatDuration(Duration duration) => formatMediaDuration(duration);

/// Professional video viewer with complete playback controls, timeline scrubbing,
/// time indicators, volume toggle, and PiP floating window support.
class VideoViewer extends StatefulWidget {
  const VideoViewer({
    required this.item,
    required this.active,
    required this.items,
    required this.initialIndex,
    this.heroTag,
    this.isDragging = false,
    super.key,
  });

  final MediaPreviewItem item;
  final bool active;
  final List<MediaPreviewItem> items;
  final int initialIndex;
  final Object? heroTag;
  final bool isDragging;

  @override
  State<VideoViewer> createState() => _VideoViewerState();
}

class _VideoViewerState extends State<VideoViewer>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  late final VideoPlaybackSession _session;
  bool _showControls = true;
  Timer? _hideTimer;
  bool _isDraggingSlider = false;
  double _sliderValue = 0.0;
  bool _isMuted = false;
  bool _hasShownErrorToast = false;
  bool _autoPlayRequested = false;

  @override
  void initState() {
    super.initState();
    _session = VideoPlaybackSessionRegistry.obtain(
      _sessionId,
      widget.item.source,
    );
    _session.addListener(_onSessionChanged);
    unawaited(_initializeAndAutoPlay());
    _startHideTimer();
  }

  Future<void> _initializeAndAutoPlay() async {
    await _session.initialize();
    if (!mounted || _autoPlayRequested || !_session.isReady) return;
    _autoPlayRequested = true;
    await _session.controller?.play();
  }

  @override
  void didUpdateWidget(VideoViewer old) {
    super.didUpdateWidget(old);
    if (!widget.active) {
      _session.controller?.pause();
    }
  }

  String _formatErrorMessage(Object? error) {
    if (error == null) return '未知错误';
    final str = error.toString();
    if (str.contains('本地视频文件不存在') ||
        str.contains('FileNotFoundException') ||
        str.contains('ENOENT')) {
      return '本地视频文件不存在或已被清理';
    }
    if (str.contains('Source error') || str.contains('ExoPlaybackException')) {
      return '视频资源加载失败或格式不支持';
    }
    if (str.contains('PlatformException')) {
      return '播放器解析失败';
    }
    return str;
  }

  void _onSessionChanged() {
    if (mounted) {
      if (_session.error != null && !_hasShownErrorToast) {
        _hasShownErrorToast = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          showToast(
            '视频加载失败: ${_formatErrorMessage(_session.error)}',
            type: ToastType.error,
          );
        });
      }
      // video_player may notify while a gesture's build is in progress.
      // Scheduling avoids markNeedsBuild during that framework phase.
      if (SchedulerBinding.instance.schedulerPhase ==
          SchedulerPhase.persistentCallbacks) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      } else {
        setState(() {});
      }
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 3500), () {
      if (mounted &&
          _session.controller?.value.isPlaying == true &&
          !_isDraggingSlider) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _startHideTimer();
    }
  }

  void _togglePlayPause() {
    _session.togglePlayback();
    if (_session.controller?.value.isPlaying == false) {
      _startHideTimer();
    }
  }

  void _toggleMute() {
    final controller = _session.controller;
    if (controller == null) return;
    setState(() {
      _isMuted = !_isMuted;
      controller.setVolume(_isMuted ? 0.0 : 1.0);
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _session.removeListener(_onSessionChanged);
    VideoPlaybackSessionRegistry.release(_sessionId, _session);
    super.dispose();
  }

  String get _sessionId => 'video:${widget.item.messageId}:${widget.item.id}';

  @override
  Widget build(BuildContext context) {
    super.build(context);

    Widget buildCover() {
      final thumb = widget.item.thumbnail ?? widget.item.source;
      if (thumb.isEmpty) return const SizedBox.shrink();
      return Image(
        image: createImageProvider(thumb),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    }

    if (_session.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white70, size: 48),
            const SizedBox(height: 12),
            Text(
              '视频加载失败：${_formatErrorMessage(_session.error)}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final controller = _session.controller;
    if (controller == null || !controller.value.isInitialized) {
      Widget loading = Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          buildCover(),
          const Center(
            child: Icon(
              Icons.play_circle_fill_rounded,
              color: Colors.white70,
              size: 64,
            ),
          ),
        ],
      );
      if (widget.heroTag != null) {
        loading = Hero(tag: widget.heroTag!, child: loading);
      }
      return Material(type: MaterialType.transparency, child: loading);
    }

    final value = controller.value;
    final duration = value.duration;
    final position = value.position;
    final isCompleted = position >= duration && duration > Duration.zero;

    final progress =
        duration.inMilliseconds > 0
            ? (position.inMilliseconds / duration.inMilliseconds).clamp(
              0.0,
              1.0,
            )
            : 0.0;

    final content = Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        child: Stack(
          alignment: Alignment.center,
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: value.aspectRatio,
                child: Stack(
                  fit: StackFit.expand,
                  children: [buildCover(), VideoPlayer(controller)],
                ),
              ),
            ),
            if (value.isBuffering)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            if ((_showControls || !value.isPlaying || isCompleted) &&
                !widget.isDragging)
              Center(
                child: Opacity(
                  opacity: 0.8,
                  child: IconButton(
                    iconSize: 64,
                    onPressed: _togglePlayPause,
                    icon: Icon(
                      isCompleted
                          ? Icons.replay_circle_filled
                          : value.isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_fill,
                      color: Colors.white.withValues(alpha: 0.9),
                      shadows: const [
                        Shadow(blurRadius: 8, color: Colors.black54),
                      ],
                    ),
                  ),
                ),
              ),
            if (_showControls && !widget.isDragging)
              Positioned(
                left: 0,
                right: 0,
                bottom: 56,
                child: Opacity(
                  opacity: 0.8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.7),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          iconSize: 28,
                          color: Colors.white,
                          onPressed: _togglePlayPause,
                          icon: Icon(
                            value.isPlaying ? Icons.pause : Icons.play_arrow,
                          ),
                        ),
                        Text(
                          _formatDuration(position),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 14,
                              ),
                              activeTrackColor:
                                  Theme.of(context).colorScheme.primary,
                              inactiveTrackColor: Colors.white24,
                              thumbColor: Colors.white,
                            ),
                            child: Slider(
                              value:
                                  _isDraggingSlider ? _sliderValue : progress,
                              onChangeStart: (val) {
                                _isDraggingSlider = true;
                                _sliderValue = val;
                                _hideTimer?.cancel();
                              },
                              onChanged: (val) {
                                setState(() {
                                  _sliderValue = val;
                                });
                              },
                              onChangeEnd: (val) async {
                                _isDraggingSlider = false;
                                final targetMs =
                                    (val * duration.inMilliseconds).toInt();
                                await controller.seekTo(
                                  Duration(milliseconds: targetMs),
                                );
                                _startHideTimer();
                              },
                            ),
                          ),
                        ),
                        Text(
                          _formatDuration(duration),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          iconSize: 22,
                          color: Colors.white,
                          tooltip: _isMuted ? '取消静音' : '静音',
                          onPressed: _toggleMute,
                          icon: Icon(
                            _isMuted ? Icons.volume_off : Icons.volume_up,
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

    if (widget.heroTag != null) {
      return Hero(tag: widget.heroTag!, child: content);
    }
    return content;
  }
}

/// 打开视频小窗口播放（悬浮画中画模式）。
void openFloatingVideoWindow(
  BuildContext context, {
  required MediaPreviewItem item,
  List<MediaPreviewItem>? items,
  int initialIndex = 0,
}) {
  final manager = FloatingWindowScope.of(context);
  final id = 'video:${item.messageId}:${item.id}';

  // 若小窗口已经存在，直接激活并置顶
  if (manager.restore(id)) return;

  final session = VideoPlaybackSessionRegistry.obtain(id, item.source)
    ..initialize();

  void restoreToFullscreen() {
    manager.close(id);
    if (items != null && items.isNotEmpty) {
      final nav =
          rootNavigatorKey.currentState ??
          Navigator.maybeOf(context, rootNavigator: true) ??
          Navigator.maybeOf(context);
      if (nav != null) {
        MediaPreview.openWithNavigator(
          nav,
          items: items,
          initialIndex: initialIndex,
        );
      }
    }
  }

  manager.show(
    id: id,
    type: FloatingWindowType.video,
    options: FloatingWindowOptions.video(),
    onRestore: restoreToFullscreen,
    child: FloatingVideoContent(
      session: session,
      autoPlay: true,
      onClose: () {
        VideoPlaybackSessionRegistry.release(id, session);
        manager.close(id);
      },
      onRestore: restoreToFullscreen,
    ),
  );
}

class FloatingVideoContent extends StatefulWidget {
  const FloatingVideoContent({
    required this.session,
    required this.onClose,
    required this.onRestore,
    this.autoPlay = false,
    super.key,
  });

  final VideoPlaybackSession session;
  final VoidCallback onClose;
  final VoidCallback onRestore;
  final bool autoPlay;

  @override
  State<FloatingVideoContent> createState() => _FloatingVideoContentState();
}

class _FloatingVideoContentState extends State<FloatingVideoContent> {
  bool _autoPlayScheduled = false;
  @override
  void initState() {
    super.initState();
    widget.session.addListener(_refresh);
    _requestAutoPlay();
  }

  @override
  void dispose() {
    widget.session.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    _requestAutoPlay();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  void _requestAutoPlay() {
    if (!widget.autoPlay || _autoPlayScheduled || !widget.session.isReady)
      return;
    _autoPlayScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await widget.session.controller?.play();
    });
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
    return Material(
      type: MaterialType.transparency,
      child: Stack(
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
            child: IconButton(
              tooltip: controller.value.isPlaying ? '暂停播放' : '播放视频',
              onPressed: widget.session.togglePlayback,
              icon: Icon(
                controller.value.isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_fill,
                size: 44,
                color: Colors.white.withValues(alpha: 0.9),
                shadows: const [Shadow(blurRadius: 6, color: Colors.black54)],
              ),
            ),
          ),
          Positioned(
            left: 2,
            top: 2,
            child: Opacity(
              opacity: 0.8,
              child: IconButton(
                tooltip: '恢复全屏播放',
                onPressed: widget.onRestore,
                icon: const Icon(Icons.fullscreen, color: Colors.white),
              ),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: Opacity(
              opacity: 0.8,
              child: IconButton(
                tooltip: '关闭视频',
                onPressed: widget.onClose,
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (controller.value.position > Duration.zero)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            formatMediaDuration(controller.value.position),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        )
                      else
                        const SizedBox.shrink(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          formatMediaDuration(controller.value.duration),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                LinearProgressIndicator(
                  value:
                      controller.value.duration.inMilliseconds > 0
                          ? (controller.value.position.inMilliseconds /
                                  controller.value.duration.inMilliseconds)
                              .clamp(0.0, 1.0)
                          : 0.0,
                  minHeight: 2,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
