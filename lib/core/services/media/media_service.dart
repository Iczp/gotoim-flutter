import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as image;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../platform/platform_contract.dart';
import '../file/file_picker_service.dart';
import 'video_processing.dart';
import 'video_processing_models.dart';

enum MediaSource { gallery, camera }

enum ImageOutputFormat { jpeg, png, webp }

class MediaPickRequest {
  const MediaPickRequest({
    this.allowMultiple = false,
    this.preserveOriginal = true,
    this.imageQuality,
    this.maxWidth,
    this.maxHeight,
    this.maxDuration,
  });

  final bool allowMultiple;
  final bool preserveOriginal;
  final int? imageQuality;
  final double? maxWidth;
  final double? maxHeight;
  final Duration? maxDuration;

  int? get effectiveImageQuality =>
      preserveOriginal ? null : (imageQuality ?? 85).clamp(0, 100).toInt();
}

class ImageCompressionRequest {
  const ImageCompressionRequest({
    this.quality = 85,
    this.maxWidth,
    this.maxHeight,
    this.format = ImageOutputFormat.jpeg,
  });

  final int quality;
  final int? maxWidth;
  final int? maxHeight;
  final ImageOutputFormat format;
}

class ProcessedImage {
  const ProcessedImage({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    required this.width,
    required this.height,
    required this.originalSize,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
  final int width;
  final int height;
  final int originalSize;

  Map<String, Object> toJson() => <String, Object>{
    'fileName': fileName,
    'mimeType': mimeType,
    'size': bytes.lengthInBytes,
    'originalSize': originalSize,
    'width': width,
    'height': height,
  };
}

class AudioRecordingRequest {
  const AudioRecordingRequest({
    this.fileNamePrefix = 'gotoim_recording',
    this.sampleRate = 44100,
    this.bitRate = 128000,
    this.numChannels = 1,
  });

  final String fileNamePrefix;
  final int sampleRate;
  final int bitRate;
  final int numChannels;
}

/// Unified camera/gallery, media processing and recording capability.
abstract class MediaService {
  Future<List<SelectedFile>> chooseImage(MediaPickRequest request);

  Future<SelectedFile?> takePhoto(MediaPickRequest request);

  Future<SelectedFile?> chooseVideo(MediaPickRequest request);

  Future<SelectedFile?> recordVideo(MediaPickRequest request);

  Future<ProcessedImage> compressImage(
    SelectedFile source,
    ImageCompressionRequest request,
  );

  Future<VideoMetadata> getVideoMetadata(SelectedFile source);

  Future<Uint8List> createVideoThumbnail(
    SelectedFile source, {
    int quality = 80,
    int positionMs = 0,
  });

  Future<SelectedFile?> compressVideo(
    SelectedFile source, {
    VideoCompressionQuality quality = VideoCompressionQuality.medium,
    bool includeAudio = true,
  });

  Future<void> startAudioRecording(AudioRecordingRequest request);

  Future<void> pauseAudioRecording();

  Future<void> resumeAudioRecording();

  Future<SelectedFile?> stopAudioRecording();

  Future<void> cancelAudioRecording();
}

class DefaultMediaService implements MediaService {
  DefaultMediaService({
    required PlatformFacade platformFacade,
    ImagePicker? imagePicker,
    AudioRecorder? audioRecorder,
    VideoProcessingService? videoProcessingService,
  }) : _platformFacade = platformFacade,
       _imagePicker = imagePicker ?? ImagePicker(),
       _audioRecorder = audioRecorder ?? AudioRecorder(),
       _videoProcessingService =
           videoProcessingService ??
           createVideoProcessingService(
             isSupported: _supportsNativeVideoProcessing(platformFacade.kind),
           );

  final PlatformFacade _platformFacade;
  final ImagePicker _imagePicker;
  final AudioRecorder _audioRecorder;
  final VideoProcessingService _videoProcessingService;

  @override
  Future<List<SelectedFile>> chooseImage(MediaPickRequest request) async {
    final files = <XFile>[];
    if (request.allowMultiple) {
      files.addAll(
        await _imagePicker.pickMultiImage(
          maxWidth: request.preserveOriginal ? null : request.maxWidth,
          maxHeight: request.preserveOriginal ? null : request.maxHeight,
          imageQuality: request.effectiveImageQuality,
        ),
      );
    } else {
      final file = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: request.preserveOriginal ? null : request.maxWidth,
        maxHeight: request.preserveOriginal ? null : request.maxHeight,
        imageQuality: request.effectiveImageQuality,
      );
      if (file != null) files.add(file);
    }
    return Future.wait(files.map(SelectedFile.fromXFile));
  }

  @override
  Future<SelectedFile?> takePhoto(MediaPickRequest request) =>
      _pickOneImage(ImageSource.camera, request);

  @override
  Future<SelectedFile?> chooseVideo(MediaPickRequest request) =>
      _pickVideo(ImageSource.gallery, request);

  @override
  Future<SelectedFile?> recordVideo(MediaPickRequest request) =>
      _pickVideo(ImageSource.camera, request);

  @override
  Future<ProcessedImage> compressImage(
    SelectedFile source,
    ImageCompressionRequest request,
  ) async {
    final input = await source.readBytes();
    final decoded = image.decodeImage(input);
    if (decoded == null) {
      throw const MediaCapabilityException('无法解码图片，不能压缩。');
    }
    final resized =
        request.maxWidth == null && request.maxHeight == null
            ? decoded
            : image.copyResize(
              decoded,
              width: request.maxWidth,
              height: request.maxHeight,
              maintainAspect: true,
            );
    final quality = request.quality.clamp(0, 100).toInt();
    final bytes = switch (request.format) {
      ImageOutputFormat.jpeg => image.encodeJpg(resized, quality: quality),
      ImageOutputFormat.png => image.encodePng(resized),
      ImageOutputFormat.webp => image.encodeWebP(resized),
    };
    final extension = switch (request.format) {
      ImageOutputFormat.jpeg => 'jpg',
      ImageOutputFormat.png => 'png',
      ImageOutputFormat.webp => 'webp',
    };
    final mimeType = switch (request.format) {
      ImageOutputFormat.jpeg => 'image/jpeg',
      ImageOutputFormat.png => 'image/png',
      ImageOutputFormat.webp => 'image/webp',
    };
    final baseName = source.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
    return ProcessedImage(
      bytes: Uint8List.fromList(bytes),
      fileName: '${baseName}_compressed.$extension',
      mimeType: mimeType,
      width: resized.width,
      height: resized.height,
      originalSize: input.lengthInBytes,
    );
  }

  @override
  Future<VideoMetadata> getVideoMetadata(SelectedFile source) =>
      _videoProcessingService.getMetadata(_requireNativePath(source));

  @override
  Future<Uint8List> createVideoThumbnail(
    SelectedFile source, {
    int quality = 80,
    int positionMs = 0,
  }) => _videoProcessingService.createThumbnail(
    _requireNativePath(source),
    quality: quality,
    positionMs: positionMs,
  );

  @override
  Future<SelectedFile?> compressVideo(
    SelectedFile source, {
    VideoCompressionQuality quality = VideoCompressionQuality.medium,
    bool includeAudio = true,
  }) async {
    final result = await _videoProcessingService.compress(
      _requireNativePath(source),
      quality: quality,
      includeAudio: includeAudio,
    );
    return result == null ? null : SelectedFile.fromXFile(XFile(result.path));
  }

  @override
  Future<void> startAudioRecording(AudioRecordingRequest request) async {
    if (!await _audioRecorder.hasPermission()) {
      throw const MediaCapabilityException('麦克风权限未授予。');
    }
    final outputPath = await _recordingPath(request);
    await _audioRecorder.start(
      RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: request.sampleRate,
        bitRate: request.bitRate,
        numChannels: request.numChannels,
      ),
      path: outputPath,
    );
  }

  @override
  Future<void> pauseAudioRecording() => _audioRecorder.pause();

  @override
  Future<void> resumeAudioRecording() => _audioRecorder.resume();

  @override
  Future<SelectedFile?> stopAudioRecording() async {
    final path = await _audioRecorder.stop();
    return path == null ? null : SelectedFile.fromXFile(XFile(path));
  }

  @override
  Future<void> cancelAudioRecording() async {
    await _audioRecorder.cancel();
  }

  Future<SelectedFile?> _pickOneImage(
    ImageSource source,
    MediaPickRequest request,
  ) async {
    final file = await _imagePicker.pickImage(
      source: source,
      maxWidth: request.preserveOriginal ? null : request.maxWidth,
      maxHeight: request.preserveOriginal ? null : request.maxHeight,
      imageQuality: request.effectiveImageQuality,
    );
    return file == null ? null : SelectedFile.fromXFile(file);
  }

  Future<SelectedFile?> _pickVideo(
    ImageSource source,
    MediaPickRequest request,
  ) async {
    final file = await _imagePicker.pickVideo(
      source: source,
      maxDuration: request.maxDuration,
    );
    return file == null ? null : SelectedFile.fromXFile(file);
  }

  String _requireNativePath(SelectedFile file) {
    if (file.originalPath == null || !_videoProcessingService.isSupported) {
      throw const MediaCapabilityException('当前平台或该文件来源不支持本地视频处理。');
    }
    return file.originalPath!;
  }

  Future<String> _recordingPath(AudioRecordingRequest request) async {
    if (_platformFacade.isWeb) return '${request.fileNamePrefix}.m4a';
    final directory = await getTemporaryDirectory();
    return '${directory.path}/${request.fileNamePrefix}_${DateTime.now().millisecondsSinceEpoch}.m4a';
  }

  static bool _supportsNativeVideoProcessing(PlatformKind kind) =>
      kind == PlatformKind.android ||
      kind == PlatformKind.ios ||
      kind == PlatformKind.macos;
}

final mediaServiceProvider = Provider<MediaService>(
  (ref) =>
      throw UnimplementedError(
        'MediaService must be provided during bootstrap.',
      ),
);
