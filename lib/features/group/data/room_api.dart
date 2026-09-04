import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/application_providers.dart';
import '../../../core/network/api_client.dart';

final roomApiProvider = Provider<RoomApi>((ref) {
  final client = ref.watch(apiClientProvider);
  return RoomApi(client);
});

/// 群组创建与管理相关 API
class RoomApi {
  RoomApi(this._client);

  final ApiClient _client;

  /// 创建群聊（面对面建群或好友建群）
  Future<Map<String, dynamic>> createRoom({
    required String name,
    required int ownerId,
    String? code,
    int type = 0,
    String? description,
    List<int>? chatObjectIdList,
  }) async {
    return _client.post<Map<String, dynamic>>(
      '/api/chat/room',
      data: <String, dynamic>{
        'name': name,
        'code': code ?? '',
        'ownerId': ownerId,
        'type': type,
        'description': description ?? name,
        'chatObjectIdList': chatObjectIdList ?? <int>[],
      },
    );
  }
}
