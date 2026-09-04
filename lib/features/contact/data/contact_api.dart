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

  /// 根据唯一编码查询聊天对象
  Future<Map<String, dynamic>> getChatObjectByCode(String code) async {
    return _client.get<Map<String, dynamic>>(
      '/api/chat/chat-object/by-code',
      query: <String, Object?>{'code': code},
    );
  }
}
