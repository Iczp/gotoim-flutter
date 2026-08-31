import '../../../core/network/api_client.dart';
import '../../session/data/models/chat_owner.dart';

/// Chat Swagger contract: POST /api/chat/chat-object/{id}/upload-portrait,
/// multipart field `file`, returns ChatObjectDto.
class ChatAvatarApi {
  ChatAvatarApi(this._apiClient);
  final ApiClient _apiClient;

  Future<ChatOwner> uploadPortrait({
    required int chatObjectId,
    required MultipartUploadFile file,
    void Function(int sent, int total)? onProgress,
  }) async {
    final json = await _apiClient.postMultipart<Map<String, dynamic>>(
      '/api/chat/chat-object/$chatObjectId/upload-portrait',
      file: file,
      fieldName: 'file',
      onProgress: onProgress,
    );
    return ChatOwner.fromJson(json);
  }
}
