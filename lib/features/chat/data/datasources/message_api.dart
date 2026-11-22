import '../../../../core/network/api_client.dart';
import '../../../session/data/models/paged_result_dto.dart';
import '../models/chat_message.dart';

class MessageApi {
  MessageApi(this._client, {this.deviceId = 'flutter-device'});
  final ApiClient _client;
  final String deviceId;

  Future<Map<String, dynamic>> pullChanges({
    required int chatObjectId,
    required String epoch,
    required String afterMessageChangeId,
    int maxResultCount = 100,
    String? deviceId,
  }) async {
    final result = await _client.post<Map<String, dynamic>>(
      '/api/chat/message-change/pull',
      data: {
        'chatObjectId': chatObjectId,
        'deviceId': deviceId ?? this.deviceId,
        'epoch': epoch,
        'afterMessageChangeId': afterMessageChangeId,
        'maxResultCount': maxResultCount,
      },
    );
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> ackChanges({
    required int chatObjectId,
    required String epoch,
    required String lastAppliedMessageChangeId,
    bool reset = false,
    String? deviceId,
  }) async {
    final result = await _client.post<Map<String, dynamic>>(
      '/api/chat/message-change/ack',
      data: {
        'chatObjectId': chatObjectId,
        'deviceId': deviceId ?? this.deviceId,
        'epoch': epoch,
        'lastAppliedMessageChangeId': lastAppliedMessageChangeId,
        'reset': reset,
      },
    );
    return Map<String, dynamic>.from(result);
  }

  Future<List<Map<String, dynamic>>> messageStates({
    required int chatObjectId,
    required String sessionUnitId,
    required List<int> messageIds,
    String? deviceId,
  }) async {
    final result = await _client.post<Map<String, dynamic>>(
      '/api/chat/message/by-ids',
      data: {
        'chatObjectId': chatObjectId,
        'deviceId': deviceId ?? this.deviceId,
        'requests': [
          {
            'sessionUnitId': sessionUnitId,
            'messageIds': messageIds.map((id) => id.toString()).toList(),
          },
        ],
      },
    );
    final items = result['items'] as List<dynamic>? ?? const [];
    return items.map((row) => Map<String, dynamic>.from(row as Map)).toList();
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
        'authoritative': true,
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

  Future<Map<String, dynamic>> getItem({
    required String sessionUnitId,
    required int messageId,
  }) async {
    final json = await _client.get<Map<String, dynamic>>(
      '/api/chat/message/item',
      query: <String, Object?>{
        'sessionUnitId': sessionUnitId,
        'messageId': messageId,
      },
    );
    return Map<String, dynamic>.from(json);
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
        'authoritative': true,
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

  Future<Map<String, dynamic>> uploadAttachment({
    required String sessionUnitId,
    required String fileName,
    required int fileLength,
    required Stream<List<int>> Function() openRead,
    int messageType = 5,
    Map<String, Object?>? extraFields,
    Map<String, MultipartUploadFile>? extraFiles,
    void Function(int sent, int total)? onProgress,
  }) {
    late final String path;
    String? mimeType;
    switch (messageType) {
      case 2:
        path = '/api/chat/attachments/upload-image/$sessionUnitId';
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
        path = '/api/chat/attachments/upload-sound/$sessionUnitId';
        mimeType = 'audio/amr';
        break;
      case 4:
        path = '/api/chat/attachments/upload-video/$sessionUnitId';
        mimeType = 'video/mp4';
        break;
      default:
        path = '/api/chat/attachments/upload-file/$sessionUnitId';
        break;
    }
    final mergedFields = <String, Object?>{...?extraFields, ...?extraFiles};
    return _client.postMultipart<Map<String, dynamic>>(
      path,
      file: MultipartUploadFile(
        name: fileName,
        length: fileLength,
        openRead: openRead,
        contentType: mimeType,
      ),
      extraFields: mergedFields.isEmpty ? null : mergedFields,
      onProgress: onProgress,
    );
  }

  Future<Map<String, dynamic>> sendAttachmentMessage({
    required String sessionUnitId,
    required int messageType,
    required Map<String, dynamic> uploadResult,
    String? clientMessageId,
    int? quoteMessageId,
    Map<String, Object?>? extraContent,
  }) {
    final safeExtraContent = <String, Object?>{
      if (extraContent != null)
        for (final entry in extraContent.entries)
          if (entry.value != null && entry.value is! MultipartUploadFile)
            entry.key: entry.value,
    };
    double? resolvedVideoDurationSec;
    if (messageType == 4) {
      final rawDuration = uploadResult['duration'] ?? safeExtraContent['durationMs'];
      final num? rawNum = rawDuration is num
          ? rawDuration
          : num.tryParse('${rawDuration ?? ''}');
      if (rawNum != null && rawNum > 0) {
        resolvedVideoDurationSec = double.parse(
          (rawNum / 1000.0).toStringAsFixed(2),
        );
      }
      safeExtraContent.remove('durationMs');
    }
    final content = <String, dynamic>{
      'blobId': uploadResult['blobId'],
      'url': uploadResult['url'],
      'fileName': uploadResult['fileName'],
      'contentType': uploadResult['contentType'],
      'suffix': uploadResult['suffix'],
      'size': uploadResult['size'],
      if (uploadResult['thumbnailBlobId'] != null)
        'thumbnailBlobId': uploadResult['thumbnailBlobId'],
      if (uploadResult['thumbnailUrl'] != null)
        'thumbnailUrl': uploadResult['thumbnailUrl'],
      if (uploadResult['originalBlobId'] != null)
        'originalBlobId': uploadResult['originalBlobId'],
      if (uploadResult['originalUrl'] != null)
        'originalUrl': uploadResult['originalUrl'],
      if (uploadResult['snapshotBlobId'] != null)
        'snapshotBlobId': uploadResult['snapshotBlobId'],
      if (uploadResult['snapshotUrl'] != null)
        'snapshotUrl': uploadResult['snapshotUrl'],
      if (uploadResult['snapshotThumbnailBlobId'] != null)
        'snapshotThumbnailBlobId': uploadResult['snapshotThumbnailBlobId'],
      if (uploadResult['snapshotThumbnailUrl'] != null)
        'snapshotThumbnailUrl': uploadResult['snapshotThumbnailUrl'],
      if (uploadResult['gifBlobId'] != null)
        'gifBlobId': uploadResult['gifBlobId'],
      if (uploadResult['gifUrl'] != null) 'gifUrl': uploadResult['gifUrl'],
      if (uploadResult['width'] != null) 'width': uploadResult['width'],
      if (uploadResult['height'] != null) 'height': uploadResult['height'],
      if (uploadResult['imageWidth'] != null)
        'imageWidth': uploadResult['imageWidth']
      else if (uploadResult['width'] != null)
        'imageWidth': uploadResult['width'],
      if (uploadResult['imageHeight'] != null)
        'imageHeight': uploadResult['imageHeight']
      else if (uploadResult['height'] != null)
        'imageHeight': uploadResult['height'],
      if (uploadResult['profile'] != null) 'profile': uploadResult['profile'],
      if (messageType == 3)
        'time': uploadResult['duration'] ?? safeExtraContent['durationMs'] ?? 0,
      if (messageType == 4 && resolvedVideoDurationSec != null)
        'duration': resolvedVideoDurationSec,
      ...safeExtraContent,
    };

    late final String sendPath;
    switch (messageType) {
      case 2:
        sendPath = '/api/chat/message-sender/send-image/$sessionUnitId';
        break;
      case 3:
        sendPath = '/api/chat/message-sender/send-sound/$sessionUnitId';
        break;
      case 4:
        sendPath = '/api/chat/message-sender/send-video/$sessionUnitId';
        break;
      default:
        sendPath = '/api/chat/message-sender/send-file/$sessionUnitId';
        break;
    }

    return _client.post<Map<String, dynamic>>(
      sendPath,
      data: <String, Object?>{
        if (clientMessageId != null && clientMessageId.isNotEmpty)
          'clientMessageId': clientMessageId,
        if (quoteMessageId != null && quoteMessageId > 0)
          'quoteMessageId': quoteMessageId,
        'content': content,
      },
    );
  }

  /// 两段式先传后发：先调用 /api/chat/attachments/upload-* 拿到服务端凭证与 URL，再调用 send-* 发消息
  Future<Map<String, dynamic>> sendUploadFile({
    required String sessionUnitId,
    required String fileName,
    required int fileLength,
    required Stream<List<int>> Function() openRead,
    int messageType = 5,
    Map<String, Object?>? extraFields,
    Map<String, MultipartUploadFile>? extraFiles,
    void Function(int sent, int total)? onProgress,
  }) async {
    final uploadResult = await uploadAttachment(
      sessionUnitId: sessionUnitId,
      fileName: fileName,
      fileLength: fileLength,
      openRead: openRead,
      messageType: messageType,
      extraFields: extraFields,
      extraFiles: extraFiles,
      onProgress: onProgress,
    );
    return sendAttachmentMessage(
      sessionUnitId: sessionUnitId,
      messageType: messageType,
      uploadResult: uploadResult,
      extraContent: extraFields,
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

  /// 上报瞬态输入状态: POST /api/chat/message-sender/send-typing/{sessionUnitId}
  Future<void> sendTyping({
    required String sessionUnitId,
    required String sessionId,
    String? senderName,
    required bool isTyping,
    String action = 'typing',
    String? actionText,
  }) async {
    try {
      await _client.post<void>(
        '/api/chat/message-sender/send-typing/$sessionUnitId',
        data: <String, Object?>{
          'sessionId': sessionId,
          'senderName': senderName ?? '我',
          'isTyping': isTyping,
          'action': action,
          if (actionText != null) 'actionText': actionText,
        },
      );
    } catch (_) {
      // 瞬态状态上报忽略失败
    }
  }
}
