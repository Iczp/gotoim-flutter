import '../../../../core/network/api_client.dart';
import '../models/contact_group.dart';
import '../../../session/data/models/paged_result_dto.dart';
import '../models/online_friend.dart';

class ContactsApi {
  ContactsApi(this._apiClient);

  final ApiClient _apiClient;

  Future<List<ContactGroup>> getIndexedFriends({required int ownerId}) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/api/chat/session-unit-cache/friends-indexed/$ownerId',
    );
    return PagedResultDto<ContactGroup>.fromJson(
      response,
      ContactGroup.fromJson,
    ).items.where((group) => group.contacts.isNotEmpty).toList(growable: false);
  }

  Future<List<OnlineFriend>> getOnlineFriends({required int ownerId}) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/api/chat/online/online-friends',
      // Swagger validates MaxResultCount in the inclusive range 1–1000.
      query: <String, Object?>{'OwnerId': ownerId, 'MaxResultCount': 1000},
    );
    return PagedResultDto<OnlineFriend>.fromJson(
      response,
      OnlineFriend.fromJson,
    ).items;
  }

  /// 增量拉取联系人变更
  Future<Map<String, dynamic>> getContactChanges({
    required int ownerId,
    required int minTicks,
    int maxResultCount = 100,
  }) async {
    return _apiClient.get<Map<String, dynamic>>(
      '/api/chat/session-unit-cache/changes',
      query: <String, Object?>{
        'ownerId': ownerId,
        'minTicks': minTicks,
        'maxResultCount': maxResultCount,
      },
    );
  }

  /// 获取联系人/会话单元详细信息（含系统条目与私有扩展条目）
  Future<Map<String, dynamic>> getContactDetail({
    required String sessionUnitId,
  }) async {
    return _apiClient.get<Map<String, dynamic>>(
      '/api/chat/session-unit/$sessionUnitId/detail',
    );
  }

  /// 获取系统字段定义列表
  Future<Map<String, dynamic>> getEntryNames({
    int maxResultCount = 100,
  }) async {
    return _apiClient.get<Map<String, dynamic>>(
      '/api/chat/entry-name',
      query: <String, Object?>{
        'MaxResultCount': maxResultCount,
      },
    );
  }

  /// 设置会话单元自定义条目
  Future<Map<String, dynamic>> setSessionUnitEntries({
    required String sessionUnitId,
    required Map<String, List<String>> entries,
  }) async {
    return _apiClient.post<Map<String, dynamic>>(
      '/api/chat/entry/set-for-session-unit/$sessionUnitId',
      data: entries,
    );
  }
}
