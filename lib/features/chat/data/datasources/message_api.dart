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

  Future<PagedResultDto<ChatMessage>> latest({
    required int ownerId,
    required String sessionUnitId,
    required int limit,
    required int minMessageId,
  }) async {
    final json = await _client.get<Map<String, dynamic>>(
      '/api/chat/message/latest',
      query: <String, Object?>{
        'sessionUnitId': sessionUnitId,
        'maxResultCount': limit,
        'minMessageId': minMessageId,
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

  Future<Map<String, dynamic>> sendUploadFile({
    required String sessionUnitId,
    required String fileName,
    required int fileLength,
    required Stream<List<int>> Function() openRead,
  }) => _client.postMultipart<Map<String, dynamic>>(
    '/api/chat/message-sender/send-upload-file/$sessionUnitId',
    file: MultipartUploadFile(
      name: fileName,
      length: fileLength,
      openRead: openRead,
    ),
  );
}
