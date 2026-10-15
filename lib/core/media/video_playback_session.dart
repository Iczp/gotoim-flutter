import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import 'media_preview.dart';
import 'video_controller_factory.dart';

/// Owns a single video controller so a full-screen view and a floating view
/// can hand off playback without restarting the media.
class VideoPlaybackSession extends ChangeNotifier {
  VideoPlaybackSession(
    this.source, {
    this.localPath,
    this.item,
  });

  VideoPlaybackSession.network(this.source)
      : localPath = null,
        item = null;

  final String source;
  String? localPath;
  MediaPreviewItem? item;

  VideoPlayerController? _controller;
  Object? _error;
  bool _initializing = false;
  bool _disposed = false;

  VideoPlayerController? get controller => _controller;
  Object? get error => _error;
  bool get isReady => _controller?.value.isInitialized ?? false;

  Future<void> initialize({bool force = false}) async {
    if (_disposed || _initializing) return;
    if (_controller != null && !force && _error == null) return;
    _initializing = true;
    _error = null;
    notifyListeners();

    if (force && _controller != null) {
      final old = _controller;
      _controller = null;
      old?.removeListener(notifyListeners);
      try {
        await old?.dispose();
      } catch (_) {}
    }

    try {
      String effectiveSource = source;

      // 1. 检查显式传入的 localPath 本地缓存文件
      if (localPath != null && localPath!.isNotEmpty && !kIsWeb) {
        try {
          if (File(localPath!).existsSync()) {
            effectiveSource = localPath!;
          }
        } catch (_) {}
      }

      // 2. 若仍为网络地址，主动探测 AttachmentCache 磁盘缓存（例如此前全屏播放或转存时已下载的文件）
      if ((effectiveSource.startsWith('http://') ||
              effectiveSource.startsWith('https://')) &&
          !kIsWeb) {
        try {
          final probeItem = item ??
              MediaPreviewItem(
                id: source,
                messageId: source,
                type: MediaPreviewType.video,
                source: source,
                localPath: localPath,
                heroTag: source,
              );
          final cached =
              await DefaultMediaDownloader.instance.getCachedPath(probeItem);
          if (cached != null && File(cached).existsSync()) {
            effectiveSource = cached;
            localPath = cached;
          }
        } catch (_) {}
      }

      final controller = createVideoController(effectiveSource);
      await controller.initialize();
      if (_disposed) {
        await controller.dispose();
        return;
      }
      _controller = controller..addListener(notifyListeners);

      // 3. 若使用远端网络播放且包含有效 item，在后台静默缓存，下次离线即可秒播
      if ((effectiveSource.startsWith('http://') ||
              effectiveSource.startsWith('https://')) &&
          item != null &&
          !kIsWeb) {
        unawaited(
          DefaultMediaDownloader.instance.download(item!).then((path) {
            localPath = path;
          }).catchError((_) {}),
        );
      }
    } catch (error) {
      _error = error;
    } finally {
      _initializing = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> togglePlayback() async {
    if (_disposed) return;
    final controller = _controller;
    if (controller == null) return;
    try {
      // A close action can dispose the controller while a queued tap gesture
      // is still resolving. Only use the controller while this session still
      // owns that exact instance.
      if (_disposed || !identical(_controller, controller)) return;
      if (controller.value.isPlaying) {
        await controller.pause();
      } else {
        await controller.play();
      }
    } catch (error) {
      // Native teardown can race with an already accepted tap. The session is
      // gone in that case, so there is no useful playback error to surface.
      if (_disposed || !identical(_controller, controller)) return;
      _error = error;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    final controller = _controller;
    // Clear the public reference before disposing. Any late gesture then sees
    // no playable controller instead of calling into a disposed notifier.
    _controller = null;
    controller?.removeListener(notifyListeners);
    controller?.dispose();
    super.dispose();
  }
}

/// Keeps a playback session alive while its visual host moves between the
/// media preview route and the app-level floating window.
abstract final class VideoPlaybackSessionRegistry {
  static final Map<String, VideoPlaybackSession> _sessions =
      <String, VideoPlaybackSession>{};
  static final Map<String, int> _references = <String, int>{};

  /// Each visual host (full screen or floating window) owns one reference.
  /// This lets a controller survive the handoff between those two surfaces.
  static VideoPlaybackSession obtain(
    String id,
    String source, {
    String? localPath,
    MediaPreviewItem? item,
  }) {
    var session = _sessions[id];
    if (session == null) {
      session = VideoPlaybackSession(
        source,
        localPath: localPath,
        item: item,
      );
      _sessions[id] = session;
    } else {
      if (localPath != null && session.localPath == null) {
        session.localPath = localPath;
      }
      if (item != null && session.item == null) {
        session.item = item;
      }
    }
    _references[id] = (_references[id] ?? 0) + 1;
    return session;
  }

  static void release(String id, VideoPlaybackSession session) {
    if (!identical(_sessions[id], session)) return;
    final remaining = (_references[id] ?? 1) - 1;
    if (remaining > 0) {
      _references[id] = remaining;
      return;
    }
    _references.remove(id);
    _sessions.remove(id);
    session.dispose();
  }
}
