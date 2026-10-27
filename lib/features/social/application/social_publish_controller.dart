import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_exception.dart';
import '../data/social_repository.dart';

class SocialPublishController extends ChangeNotifier {
  SocialPublishController(this._repository, {this.actor});
  final SocialActor? actor;
  final SocialRepository _repository;
  bool submitting = false;
  String? error;
  String? _fingerprint;
  String _commandId = const Uuid().v4();
  bool _disposed = false;

  Future<SocialPost?> publish(String text, {int visibility = 0}) async {
    if (_disposed || submitting) return null;
    final content = text.trim();
    if (content.isEmpty || content.length > 2000) {
      error = '请输入 1–2000 字的动态内容。';
      notifyListeners();
      return null;
    }
    final fingerprint = '$visibility|$content';
    if (_fingerprint != fingerprint) {
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
      return await _repository.publish(
        actorId: actor.id,
        content: content,
        clientRequestId: _commandId,
        visibility: visibility,
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
