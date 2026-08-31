import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../app/application_providers.dart';
import '../../../core/config/app_environment.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/media/media_service.dart';
import '../../../core/widgets/avatar_preferences.dart';
import '../../../core/utils/api_url_resolver.dart';
import '../../media/application/avatar_crop_service.dart';
import '../../session/application/session_list_controller.dart';
import '../data/chat_avatar_api.dart';

enum AvatarEditStatus { idle, picking, cropping, uploading, success, failed }

class AvatarEditController extends ChangeNotifier {
  AvatarEditController({
    required AvatarCropService cropper,
    required ChatAvatarApi api,
    required SessionListController sessions,
    required String apiBaseUrl,
  }) : _cropper = cropper,
       _api = api,
       _sessions = sessions,
       _apiBaseUrl = apiBaseUrl;

  final AvatarCropService _cropper;
  final ChatAvatarApi _api;
  final SessionListController _sessions;
  final String _apiBaseUrl;
  AvatarEditStatus _status = AvatarEditStatus.idle;
  double? _progress;
  Object? _error;
  AvatarEditStatus get status => _status;
  double? get progress => _progress;
  Object? get error => _error;

  Future<void> chooseCropAndUpload(AvatarShape shape) async {
    final owner = _sessions.currentOwner;
    if (owner == null || _status == AvatarEditStatus.uploading) return;
    _status = AvatarEditStatus.picking;
    _error = null;
    notifyListeners();
    try {
      final file = await _cropper.chooseAndCrop(previewShape: shape);
      if (file == null) {
        _status = AvatarEditStatus.idle;
        notifyListeners();
        return;
      }
      _status = AvatarEditStatus.uploading;
      _progress = 0;
      notifyListeners();
      final updated = await _api.uploadPortrait(
        chatObjectId: owner.id,
        file: MultipartUploadFile(
          name: file.name,
          length: file.size,
          openRead: file.readAsByteStream,
        ),
        onProgress: (sent, total) {
          _progress = total > 0 ? sent / total : null;
          notifyListeners();
        },
      );
      await _evictAvatar(owner.imageUrl);
      await _evictAvatar(updated.imageUrl);
      await _sessions.updateCurrentOwner(updated);
      _status = AvatarEditStatus.success;
    } catch (error) {
      _error = error;
      _status = AvatarEditStatus.failed;
    } finally {
      _progress = null;
      notifyListeners();
    }
  }

  Future<void> _evictAvatar(String? source) async {
    final url = resolveApiUrl(source, _apiBaseUrl);
    if (url.isNotEmpty) await CachedNetworkImage.evictFromCache(url);
  }
}

final avatarEditControllerProvider =
    ChangeNotifierProvider<AvatarEditController>(
      (ref) => AvatarEditController(
        cropper: AvatarCropService(ref.watch(mediaServiceProvider)),
        api: ChatAvatarApi(ref.watch(apiClientProvider)),
        sessions: ref.read(sessionListControllerProvider),
        apiBaseUrl: ref.watch(appEnvironmentProvider).apiBaseUrl,
      ),
    );
