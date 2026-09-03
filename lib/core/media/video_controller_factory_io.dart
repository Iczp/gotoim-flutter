import 'dart:io';
import 'package:video_player/video_player.dart';

VideoPlayerController createVideoController(String source) {
  final uri = Uri.tryParse(source);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    return VideoPlayerController.networkUrl(uri);
  }
  final path = uri?.scheme == 'file' ? uri!.toFilePath() : source;
  return VideoPlayerController.file(File(path));
}
