import 'package:video_player/video_player.dart';

VideoPlayerController createVideoController(String source) {
  final uri = Uri.tryParse(source) ?? Uri.parse(source);
  return VideoPlayerController.networkUrl(uri);
}
