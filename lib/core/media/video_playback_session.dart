import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import 'video_controller_factory.dart';

/// Owns a single video controller so a full-screen view and a floating view
/// can hand off playback without restarting the media.
class VideoPlaybackSession extends ChangeNotifier {
  VideoPlaybackSession(this.source);
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
      final controller = createVideoController(source);
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
  static VideoPlaybackSession obtain(String id, String source) {
    final session = _sessions.putIfAbsent(
      id,
      () => VideoPlaybackSession(source),
    );
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
