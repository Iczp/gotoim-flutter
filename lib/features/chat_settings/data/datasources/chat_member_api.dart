import '../../../../core/network/api_client.dart';
import '../../../session/data/models/paged_result_dto.dart';
import '../models/chat_member.dart';

class ChatMemberApi {
  ChatMemberApi(this._client);
  final ApiClient _client;

  Future<PagedResultDto<ChatMember>> getMembers({
    required String sessionUnitId,
    required int limit,
    int? maxScore,
    String? cursorId,
    String keyword = '',
  }) async {
    final json = await _client.get<Map<String, dynamic>>(
      '/api/chat/session-unit-cache/members',
      query: <String, Object?>{
        'sessionUnitId': sessionUnitId,
        'maxResultCount': limit,
        if (maxScore != null) 'maxScore': maxScore,
        if (cursorId != null) 'cursorId': cursorId,
        if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
      },
    );
    return PagedResultDto<ChatMember>.fromJson(json, ChatMember.fromJson);
  }

  Future<Map<String, dynamic>> setTopping(String id, bool value) =>
      _client.post<Map<String, dynamic>>(
        '/api/chat/session-unit-setting/set-topping/$id',
        query: <String, Object?>{'isTopping': value},
      );

  Future<Map<String, dynamic>> setImmersed(String id, bool value) =>
      _client.post<Map<String, dynamic>>(
        '/api/chat/session-unit-setting/set-immersed/$id',
        query: <String, Object?>{'isImmersed': value},
      );

  Future<Map<String, dynamic>> exitChat(String id) => _client
      .post<Map<String, dynamic>>('/api/chat/session-unit-setting/exit/$id');

  Future<Map<String, dynamic>> unsubscribeOfficial(String id) =>
      _client.post<Map<String, dynamic>>('/api/chat/official/unsubscribe/$id');

  Future<Map<String, dynamic>> clearMessages(String id) =>
      _client.post<Map<String, dynamic>>(
        '/api/chat/session-unit-setting/clear-message/$id',
      );

  Future<Map<String, dynamic>> setRename(String id, String rename) =>
      _client.post<Map<String, dynamic>>(
        '/api/chat/session-unit-setting/set-rename/$id',
        query: <String, Object?>{'rename': rename},
      );

  Future<Map<String, dynamic>> setBackgroundImage({
    required String id,
    required MultipartUploadFile file,
    void Function(int sent, int total)? onProgress,
  }) => _client.postMultipart<Map<String, dynamic>>(
    '/api/chat/session-unit-setting/set-background-image/$id',
    file: file,
    onProgress: onProgress,
  );

  Future<Map<String, dynamic>> setRoomTitle(String roomId, String title) =>
      _client.post<Map<String, dynamic>>(
        '/api/chat/room/set-title/$roomId',
        query: <String, Object?>{'title': title},
      );
}
