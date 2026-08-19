import 'dart:typed_data';

import 'video_processing_models.dart';

VideoProcessingService createVideoProcessingService({
  required bool isSupported,
}) => _UnsupportedVideoProcessingService();

class _UnsupportedVideoProcessingService implements VideoProcessingService {
  @override
  bool get isSupported => false;

  @override
  Future<VideoCompressionResult?> compress(
    String path, {
    VideoCompressionQuality quality = VideoCompressionQuality.medium,
    bool includeAudio = true,
  }) => throw const MediaCapabilityException('当前平台不支持视频压缩。');

  @override
  Future<Uint8List> createThumbnail(
    String path, {
    int quality = 80,
    int positionMs = 0,
  }) => throw const MediaCapabilityException('当前平台不支持视频缩略图。');

  @override
  Future<VideoMetadata> getMetadata(String path) =>
      throw const MediaCapabilityException('当前平台不支持读取视频信息。');
}
