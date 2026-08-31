import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

/// Owns a single video controller so a full-screen view and a floating view
/// can hand off playback without restarting the media.
class VideoPlaybackSession extends ChangeNotifier {
  VideoPlaybackSession.network(this.source);

  final String source;
  VideoPlayerController? _controller;
  Object? _error;
  bool _initializing = false;
  bool _disposed = false;

  VideoPlayerController? get controller => _controller;
  Object? get error => _error;
  bool get isReady => _controller?.value.isInitialized ?? false;

  Future<void> initialize() async {
    if (_disposed || _initializing || _controller != null) return;
    _initializing = true;
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(source));
      await controller.initialize();
      if (_disposed) {
        await controller.dispose();
        return;
      }
      _controller = controller..addListener(notifyListeners);
    } catch (error) {
      _error = error;
    } finally {
      _initializing = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> togglePlayback() async {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _controller?.removeListener(notifyListeners);
    _controller?.dispose();
    super.dispose();
  }
}

/// Keeps a playback session alive while its visual host moves between the
/// media preview route and the app-level floating window.
abstract final class VideoPlaybackSessionRegistry {
  static final Map<String, VideoPlaybackSession> _sessions =
      <String, VideoPlaybackSession>{};

  static VideoPlaybackSession obtain(String id, String source) =>
      _sessions.putIfAbsent(id, () => VideoPlaybackSession.network(source));

  static void release(String id, VideoPlaybackSession session) {
    if (!identical(_sessions[id], session)) return;
    _sessions.remove(id);
    session.dispose();
  }
}
