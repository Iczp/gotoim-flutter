import 'dart:typed_data';

enum VideoCompressionQuality { low, medium, high, original }

class VideoMetadata {
  const VideoMetadata({
    required this.durationMs,
    required this.width,
    required this.height,
    required this.size,
    required this.path,
  });

  final int? durationMs;
  final int? width;
  final int? height;
  final int? size;
  final String path;

  Map<String, Object?> toJson() => <String, Object?>{
    'durationMs': durationMs,
    'width': width,
    'height': height,
    'size': size,
    'path': path,
  };
}

class VideoCompressionResult {
  const VideoCompressionResult({required this.path, required this.metadata});

  final String path;
  final VideoMetadata metadata;
}

class MediaCapabilityException implements Exception {
  const MediaCapabilityException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class VideoProcessingService {
  bool get isSupported;

  Future<VideoMetadata> getMetadata(String path);

  Future<Uint8List> createThumbnail(
    String path, {
    int quality = 80,
    int positionMs = 0,
  });

  Future<VideoCompressionResult?> compress(
    String path, {
    VideoCompressionQuality quality = VideoCompressionQuality.medium,
    bool includeAudio = true,
  });
}
