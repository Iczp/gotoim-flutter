import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/application_providers.dart';
import '../../../core/network/api_client.dart';

final contactApiProvider = Provider<ContactApi>((ref) {
  final client = ref.watch(apiClientProvider);
  return ContactApi(client);
});

/// 联系人与加好友相关 API
class ContactApi {
  ContactApi(this._client);

  final ApiClient _client;

  /// 通讯录搜索
  Future<Map<String, dynamic>> searchContacts({
    required int ownerId,
    required String keyword,
    int maxResultCount = 20,
    List<int>? objectTypes,
  }) async {
    return _client.get<Map<String, dynamic>>(
      '/api/chat/contacts',
      query: <String, Object?>{
        'OwnerId': ownerId,
        'Keyword': keyword,
        'MaxResultCount': maxResultCount,
        if (objectTypes != null && objectTypes.isNotEmpty)
          'ObjectTypes': objectTypes,
      },
    );
  }

  /// 发起会话/加好友/加群请求
  Future<Map<String, dynamic>> createSessionRequest({
    required int ownerId,
    required int destinationId,
    String? requestMessage,
  }) async {
    return _client.post<Map<String, dynamic>>(
      '/api/chat/session-request',
      query: <String, Object?>{
        'OwnerId': ownerId,
        'DestinationId': destinationId,
        if (requestMessage != null && requestMessage.trim().isNotEmpty)
          'RequestMessage': requestMessage.trim(),
      },
    );
  }

  /// 搜索聊天对象（全局搜索用户、群聊、机器人等）
  Future<Map<String, dynamic>> searchChatObjects({
    required String keyword,
    bool isEnabledParentId = false,
    int maxResultCount = 20,
    int? objectType,
    List<int>? objectTypes,
  }) async {
    return _client.get<Map<String, dynamic>>(
      '/api/chat/chat-object',
      query: <String, Object?>{
        'Keyword': keyword,
        'IsEnabledParentId': isEnabledParentId,
        'MaxResultCount': maxResultCount,
        if (objectType != null) 'ObjectType': objectType,
        if (objectTypes != null && objectTypes.isNotEmpty)
          'ObjectTypes': objectTypes,
      },
    );
  }

  /// 根据唯一编码查询聊天对象
  Future<Map<String, dynamic>> getChatObjectByCode(String code) async {
    return _client.get<Map<String, dynamic>>(
      '/api/chat/chat-object/by-code',
      query: <String, Object?>{'code': code},
    );
  }

  /// 查询会话/加好友/加群申请详情
  Future<Map<String, dynamic>> getSessionRequestDetail(String id) async {
    return _client.get<Map<String, dynamic>>('/api/chat/session-request/$id');
  }

  /// 查询会话/加好友/加群申请列表
  Future<Map<String, dynamic>> listSessionRequests({
    int? ownerId,
    int? destinationId,
    bool? isHandled,
    int maxResultCount = 50,
  }) async {
    return _client.get<Map<String, dynamic>>(
      '/api/chat/session-request',
      query: <String, Object?>{
        if (ownerId != null) 'OwnerId': ownerId,
        if (destinationId != null) 'DestinationId': destinationId,
        if (isHandled != null) 'IsHandled': isHandled,
        'MaxResultCount': maxResultCount,
      },
    );
  }

  /// 审批会话/加好友/加群申请（支持传入群管理员的 handlerSessionUnitId）
  Future<Map<String, dynamic>> handleSessionRequest({
    required String sessionRequestId,
    required bool isAgreed,
    String? handleMessage,
    String? handlerSessionUnitId,
  }) async {
    return _client.post<Map<String, dynamic>>(
      '/api/chat/session-request/handle-request',
      query: <String, Object?>{
        'SessionRequestId': sessionRequestId,
        'IsAgreed': isAgreed,
        if (handleMessage != null && handleMessage.trim().isNotEmpty)
          'HandleMessage': handleMessage.trim(),
        if (handlerSessionUnitId != null &&
            handlerSessionUnitId.trim().isNotEmpty)
          'HandlerSessionUnitId': handlerSessionUnitId.trim(),
      },
    );
  }
}
