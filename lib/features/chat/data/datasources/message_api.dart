import '../../../../core/network/api_client.dart';
import '../../../session/data/models/paged_result_dto.dart';
import '../models/chat_message.dart';

class MessageApi {
  MessageApi(this._client);
  final ApiClient _client;

  Future<List<Map<String, dynamic>>> changeHeads({
    required int chatObjectId,
    required List<String> sessionUnitIds,
  }) async {
    final result = await _client.post<Map<String, dynamic>>(
      '/api/chat/message/changes/heads',
      data: {
        'chatObjectId': chatObjectId,
        'sessionUnitIds': sessionUnitIds,
      },
    );
    final items = result['items'] as List<dynamic>? ?? const [];
    return items.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  Future<Map<String, dynamic>> incrementalChanges({
    required int chatObjectId,
    required String sessionUnitId,
    required String epoch,
    required String changeSeq,
    int maxResultCount = 100,
  }) async {
    final result = await _client.post<Map<String, dynamic>>(
      '/api/chat/message/changes/incremental',
      data: {
        'chatObjectId': chatObjectId,
        'sessionUnitId': sessionUnitId,
        'epoch': epoch,
        'changeSeq': changeSeq,
        'maxResultCount': maxResultCount,
      },
    );
    return Map<String, dynamic>.from(result);
  }

  Future<List<Map<String, dynamic>>> messageStates({
    required int chatObjectId,
    required String sessionUnitId,
    required List<int> messageIds,
  }) async {
    final result = await _client.post<Map<String, dynamic>>(
      '/api/chat/message/by-ids',
      data: {
        'chatObjectId': chatObjectId,
        'sessionUnitId': sessionUnitId,
        'messageIds': messageIds,
      },
    );
    final items = result['items'] as List<dynamic>? ?? const [];
    return items.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  @Deprecated('Use changeHeads/incrementalChanges instead. /api/chat/message/changes/query is disabled.')
  Future<List<Map<String, dynamic>>> changes(
    List<Map<String, Object?>> sessions,
  ) async {
    throw UnsupportedError('Message Change Sync V1 (/api/chat/message/changes/query) is disabled.');
  }

  Future<List<Map<String, dynamic>>> syncItems(
    String unit,
    List<int> ids,
  ) async {
    final result = await _client.post<List<dynamic>>(
      '/api/chat/message/sync-items',
      data: {'sessionUnitId': unit, 'messageIds': ids},
    );
    return result.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

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
    int? quoteMessageId,
    List<String>? remindList,
  }) => _client.post<Map<String, dynamic>>(
    '/api/chat/message-sender/send-text/$sessionUnitId',
    data: <String, Object?>{
      'clientMessageId': clientMessageId,
      if (quoteMessageId != null) 'quoteMessageId': quoteMessageId,
      if (remindList != null && remindList.isNotEmpty) 'remindList': remindList,
      'content': <String, Object?>{'text': text},
    },
  );

  Future<Map<String, dynamic>> sendLink({
    required String sessionUnitId,
    required String clientMessageId,
    required String url,
    String? title,
    String? description,
    String? image,
    int? quoteMessageId,
    List<String>? remindList,
  }) => _client.post<Map<String, dynamic>>(
    '/api/chat/message-sender/send-link/$sessionUnitId',
    data: <String, Object?>{
      'clientMessageId': clientMessageId,
      if (quoteMessageId != null) 'quoteMessageId': quoteMessageId,
      if (remindList != null && remindList.isNotEmpty) 'remindList': remindList,
      'content': <String, Object?>{
        'url': url,
        if (title != null && title.isNotEmpty) 'title': title,
        if (description != null && description.isNotEmpty)
          'description': description,
        if (image != null && image.isNotEmpty) 'image': image,
      },
    },
  );

  Future<Map<String, dynamic>> sendUploadFile({
    required String sessionUnitId,
    required String fileName,
    required int fileLength,
    required Stream<List<int>> Function() openRead,
    int messageType = 5,
    Map<String, Object?>? extraFields,
    void Function(int sent, int total)? onProgress,
  }) {
    late final String path;
    String? mimeType;
    switch (messageType) {
      case 2:
        path = '/api/chat/message-sender/send-upload-image/$sessionUnitId';
        final lower = fileName.toLowerCase();
        if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
          mimeType = 'image/jpeg';
        } else if (lower.endsWith('.gif')) {
          mimeType = 'image/gif';
        } else if (lower.endsWith('.webp')) {
          mimeType = 'image/webp';
        } else {
          mimeType = 'image/png';
        }
        break;
      case 3:
        path = '/api/chat/message-sender/send-upload-sound/$sessionUnitId';
        mimeType = 'audio/amr';
        break;
      case 4:
        path = '/api/chat/message-sender/send-upload-video/$sessionUnitId';
        mimeType = 'video/mp4';
        break;
      default:
        path = '/api/chat/message-sender/send-upload-file/$sessionUnitId';
        break;
    }
    return _client.postMultipart<Map<String, dynamic>>(
      path,
      file: MultipartUploadFile(
        name: fileName,
        length: fileLength,
        openRead: openRead,
        contentType: mimeType,
      ),
      extraFields: extraFields,
      onProgress: onProgress,
    );
  }

  Future<Map<String, dynamic>> setRead({
    required String sessionUnitId,
    required int messageId,
  }) => _client.post<Map<String, dynamic>>(
    '/api/chat/session-unit-setting/set-read',
    query: <String, Object?>{
      'sessionUnitId': sessionUnitId,
      'messageId': messageId,
    },
  );

  Future<void> deleteMessage({
    required String sessionUnitId,
    required int messageId,
  }) => _client.post<void>(
    '/api/chat/session-unit-setting/delete-message',
    query: <String, Object?>{
      'sessionUnitId': sessionUnitId,
      'messageId': messageId,
    },
  );

  Future<void> rollback(int messageId) =>
      _client.post<void>('/api/chat/message-sender/rollback/$messageId');

  Future<List<Map<String, dynamic>>> forward({
    required String sessionUnitId,
    required int messageId,
    required List<String> targetSessionUnitIds,
  }) async {
    final value = await _client.post<List<dynamic>>(
      '/api/chat/message-sender/forward',
      query: <String, Object?>{
        'sessionUnitId': sessionUnitId,
        'messageId': messageId,
      },
      data: targetSessionUnitIds,
    );
    return value
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
  }

  /// Swagger: POST /api/chat/message-sender/send-history/{sessionUnitId}.
  /// Sends one history-card message containing the selected server message ids.
  Future<Map<String, dynamic>> sendHistory({
    required String sessionUnitId,
    required String clientMessageId,
    required List<int> messageIds,
  }) => _client.post<Map<String, dynamic>>(
    '/api/chat/message-sender/send-history/$sessionUnitId',
    data: <String, Object?>{
      'clientMessageId': clientMessageId,
      'content': <String, Object?>{'messageIdList': messageIds},
    },
  );
}
