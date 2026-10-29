import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_exception.dart';
import '../data/social_repository.dart';
import '../../../core/network/api_client.dart';

class SocialPublishController extends ChangeNotifier {
  SocialPublishController(this._repository, {this.actor});
  final SocialActor? actor;
  final SocialRepository _repository;
  bool submitting = false;
  bool uploading = false;
  int uploadIndex = 0;
  int uploadCount = 0;
  double? uploadProgress;
  String? error;
  String? _fingerprint;
  String _commandId = const Uuid().v4();
  bool _disposed = false;
  final List<Map<String, dynamic>> _uploaded = [];

  Future<SocialPost?> publish(
    String text, {
    int visibility = 0,
    List<MultipartUploadFile> images = const [],
    MultipartUploadFile? video,
    String? videoSelectionId,
  }) async {
    if (_disposed || submitting) return null;
    final content = text.trim();
    if ((content.isEmpty && images.isEmpty && video == null) ||
        content.length > 2000) {
      error = '请输入 1–2000 字的动态内容。';
      notifyListeners();
      return null;
    }
    if ((video != null && images.isNotEmpty) || images.length > 4) {
      error = '请选择最多四张图片或一个视频。';
      notifyListeners();
      return null;
    }
    if (video != null &&
        (video.length <= 0 || video.length > 100 * 1024 * 1024)) {
      error = '视频大小必须在 100 MB 以内。';
      notifyListeners();
      return null;
    }
    if (video != null &&
        !video.name.toLowerCase().endsWith('.mp4') &&
        !video.name.toLowerCase().endsWith('.webm')) {
      error = '目前仅支持 MP4 或 WebM 视频。';
      notifyListeners();
      return null;
    }
    final files = video == null ? images : [video];
    final mediaType = video == null ? 0 : 1;
    final fingerprint =
        '$visibility|$content|$mediaType|${videoSelectionId ?? ''}|${files.map((i) => '${i.name}:${i.length}').join(',')}';
    if (_fingerprint != fingerprint) {
      _uploaded.clear();
      _fingerprint = fingerprint;
      _commandId = const Uuid().v4();
    }
    submitting = true;
    error = null;
    notifyListeners();
    try {
      final actor = this.actor;
      if (actor == null) {
        throw const ApiException('请先创建当前 ChatObject 的 Social 身份。');
      }
      if (_disposed) return null;
      uploadCount = files.length;
      for (var index = _uploaded.length; index < files.length; index++) {
        uploading = true;
        uploadIndex = index + 1;
        uploadProgress = null;
        notifyListeners();
        final asset = await _repository.uploadMedia(
          actor.id,
          files[index],
          mediaType: mediaType,
          onProgress: (sent, total) {
            if (_disposed) return;
            uploadProgress = total > 0 ? (sent / total).clamp(0.0, 1.0) : null;
            notifyListeners();
          },
        );
        _uploaded.add({
          "mediaAssetId": asset["id"],
          "mediaType": mediaType,
          "sortOrder": _uploaded.length,
        });
      }
      uploading = false;
      notifyListeners();
      return await _repository.publish(
        actorId: actor.id,
        content: content,
        clientRequestId: _commandId,
        visibility: visibility,
        medias: List.of(_uploaded),
      );
    } catch (failure) {
      if (!_disposed) {
        error =
            failure is ApiException ? failure.message : '发布结果尚未确认，请重试相同内容确认结果。';
      }
      return null;
    } finally {
      if (!_disposed) {
        submitting = false;
        uploading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
