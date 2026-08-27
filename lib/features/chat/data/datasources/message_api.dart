import '../../../../core/network/api_client.dart';
import '../../../session/data/models/paged_result_dto.dart';
import '../models/chat_message.dart';

class MessageApi {
  MessageApi(this._client);
  final ApiClient _client;

  Future<PagedResultDto<ChatMessage>> history({
    required int ownerId,
    required String sessionUnitId,
    required int limit,
    int? maxMessageId,
  }) async {
    final json = await _client.get<Map<String, dynamic>>(
      '/api/chat/message/history',
      query: <String, Object?>{
        'sessionUnitId': sessionUnitId,
        'maxResultCount': limit,
        if (maxMessageId != null) 'maxMessageId': maxMessageId,
      },
    );
    return PagedResultDto<ChatMessage>.fromJson(
      json,
      (item) => ChatMessage.fromJson(
        item,
        ownerId: ownerId,
        sessionUnitId: sessionUnitId,
      ),
    );
  }

  Future<Map<String, dynamic>> sendText({
    required String sessionUnitId,
    required String clientMessageId,
    required String text,
  }) => _client.post<Map<String, dynamic>>(
    '/api/chat/message-sender/send-text/$sessionUnitId',
    data: <String, Object?>{
      'clientMessageId': clientMessageId,
      'content': <String, Object?>{'text': text},
    },
  );
}
