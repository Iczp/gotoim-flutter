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

  Future<Map<String, dynamic>> clearMessages(String id) =>
      _client.post<Map<String, dynamic>>(
        '/api/chat/session-unit-setting/clear-message/$id',
      );
}
