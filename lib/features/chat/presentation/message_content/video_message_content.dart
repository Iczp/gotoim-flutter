import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/utils/api_url_resolver.dart';
import '../../data/models/chat_message.dart';

/// Displays a video message preview and opens its player on demand.
class VideoMessageContent extends StatelessWidget {
  const VideoMessageContent({
    required this.message,
    required this.apiBaseUrl,
    required this.progress,
    super.key,
  });

  final ChatMessage message;
  final String apiBaseUrl;
  final double? progress;

  Uri? get _uri {
    final source = message.mediaUrl ?? message.localFilePath ?? '';
    if (source.isEmpty) return null;
    if (message.localFilePath != null) return Uri.file(source);
    return Uri.tryParse(resolveApiUrl(source, apiBaseUrl));
  }

  @override
  Widget build(BuildContext context) => InkWell(
    onTap:
        _uri == null
            ? null
            : () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => _VideoViewer(uri: _uri!)),
            ),
    child: SizedBox(
      width: 210,
      height: 128,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            const Icon(Icons.play_circle_fill, color: Colors.white, size: 52),
            Positioned(
              left: 8,
              right: 8,
              bottom: 7,
              child: Text(
                message.fileName.isEmpty ? '视频' : message.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white),
              ),
            ),
            if (progress != null && progress! < 1)
              CircularProgressIndicator(value: progress, color: Colors.white),
          ],
        ),
      ),
    ),
  );
}

class _VideoViewer extends StatefulWidget {
  const _VideoViewer({required this.uri});
  final Uri uri;

  @override
  State<_VideoViewer> createState() => _VideoViewerState();
}

class _VideoViewerState extends State<_VideoViewer> {
  late final VideoPlayerController _controller;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(widget.uri)
      ..initialize()
          .then((_) {
            if (mounted) setState(() {});
          })
          .catchError((Object error) {
            if (mounted) setState(() => _error = error);
          });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
    ),
    body: Center(
      child:
          _error != null
              ? Text(
                '视频加载失败：$_error',
                style: const TextStyle(color: Colors.white),
              )
              : !_controller.value.isInitialized
              ? const CircularProgressIndicator()
              : GestureDetector(
                onTap:
                    () => setState(
                      () =>
                          _controller.value.isPlaying
                              ? _controller.pause()
                              : _controller.play(),
                    ),
                child: AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: VideoPlayer(_controller),
                ),
              ),
    ),
  );
}
