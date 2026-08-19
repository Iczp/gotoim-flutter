import 'dart:typed_data';

import 'package:video_compress/video_compress.dart';

import 'video_processing_models.dart';

VideoProcessingService createVideoProcessingService({
  required bool isSupported,
}) => _NativeVideoProcessingService(isSupported: isSupported);

class _NativeVideoProcessingService implements VideoProcessingService {
  const _NativeVideoProcessingService({required this.isSupported});

  @override
  final bool isSupported;

  @override
  Future<VideoMetadata> getMetadata(String path) async {
    _ensureSupported();
    final info = await VideoCompress.getMediaInfo(path);
    return _metadata(info, path);
  }

  @override
  Future<Uint8List> createThumbnail(
    String path, {
    int quality = 80,
    int positionMs = 0,
  }) async {
    _ensureSupported();
    final bytes = await VideoCompress.getByteThumbnail(
      path,
      quality: quality.clamp(1, 100),
      position: positionMs,
    );
    if (bytes == null) {
      throw const MediaCapabilityException('无法生成视频缩略图。');
    }
    return bytes;
  }

  @override
  Future<VideoCompressionResult?> compress(
    String path, {
    VideoCompressionQuality quality = VideoCompressionQuality.medium,
    bool includeAudio = true,
  }) async {
    _ensureSupported();
    final info = await VideoCompress.compressVideo(
      path,
      quality: _quality(quality),
      deleteOrigin: false,
      includeAudio: includeAudio,
    );
    if (info == null || info.isCancel == true || info.path == null) return null;
    return VideoCompressionResult(
      path: info.path!,
      metadata: _metadata(info, info.path!),
    );
  }

  void _ensureSupported() {
    if (!isSupported) {
      throw const MediaCapabilityException('当前平台不支持视频处理。');
    }
  }

  VideoMetadata _metadata(MediaInfo info, String fallbackPath) => VideoMetadata(
    durationMs: info.duration?.round(),
    width: info.width,
    height: info.height,
    size: info.filesize,
    path: info.path ?? fallbackPath,
  );

  VideoQuality _quality(VideoCompressionQuality value) => switch (value) {
    VideoCompressionQuality.low => VideoQuality.LowQuality,
    VideoCompressionQuality.medium => VideoQuality.MediumQuality,
    VideoCompressionQuality.high => VideoQuality.HighestQuality,
    VideoCompressionQuality.original => VideoQuality.DefaultQuality,
  };
}
