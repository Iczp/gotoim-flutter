import 'package:video_player/video_player.dart';

VideoPlayerController createVideoController(
  String source, {
  Map<String, String> httpHeaders = const <String, String>{},
}) {
  final uri = Uri.tryParse(source) ?? Uri.parse(source);
  return VideoPlayerController.networkUrl(uri, httpHeaders: httpHeaders);
}
