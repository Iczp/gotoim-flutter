import '../../../../core/network/api_client.dart';
import '../models/paged_result_dto.dart';
import '../models/chat_owner.dart';
import '../models/session_summary.dart';
import '../models/logged_in_device.dart';

/// ABP session-unit cache endpoints used by the conversation list.
class SessionUnitApi {
  SessionUnitApi(this._apiClient);

  final ApiClient _apiClient;

  Future<List<ChatOwner>> getOwners() async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/api/chat/chat-object/by-current-user',
    );
    final page = PagedResultDto<ChatOwner>.fromJson(
      response,
      ChatOwner.fromJson,
    );
    final badges = await getOverviewBadges();
    return page.items
        .map((owner) {
          final badge = badges[owner.id];
          return owner.withOverview(
            unread: badge?.unread ?? 0,
            immersed: badge?.immersed ?? 0,
          );
        })
        .toList(growable: false);
  }

  Future<Map<int, ({int unread, int immersed})>> getOverviewBadges() async {
    final badges = <int, ({int unread, int immersed})>{};
    try {
      final overview = await _apiClient.get<Map<String, dynamic>>(
        '/api/chat/session-unit-cache/overview',
      );
      final rawOverviews = overview['overviews'];
      if (rawOverviews is List) {
        for (final raw in rawOverviews.whereType<Map>()) {
          final ownerId = raw['ownerId'];
          final id =
              ownerId is num ? ownerId.toInt() : int.tryParse('$ownerId');
          if (id == null) continue;
          final stat = raw['stat'] is Map ? raw['stat'] as Map : const {};
          badges[id] = (
            unread: (raw['totalUnreadCount'] as num?)?.toInt() ?? 0,
            immersed: (stat['immersed'] as num?)?.toInt() ?? 0,
          );
        }
      }
    } on Object {
      // Overview badges are supplementary; owner switching must remain usable.
    }
    return badges;
  }

  Future<PagedResultDto<SessionSummary>> getFriends({
    required int ownerId,
    int maxResultCount = 100,
    int? maxMessageId,
    int? maxScore,
    String? cursorId,
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/api/chat/session-unit-cache/friends',
      query: <String, Object?>{
        'ownerId': ownerId,
        'maxResultCount': maxResultCount,
        if (maxMessageId != null) 'maxMessageId': maxMessageId,
        if (maxScore != null) 'maxScore': maxScore,
        if (cursorId != null) 'cursorId': cursorId,
      },
    );
    return PagedResultDto<SessionSummary>.fromJson(
      response,
      SessionSummary.fromJson,
    );
  }

  Future<SessionSummary> getFriendDetail({
    required int ownerId,
    required String sessionUnitId,
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/api/chat/session-unit-cache/friend/$sessionUnitId',
    );
    return SessionSummary.fromJson(<String, dynamic>{
      ...response,
      'id': response['id'] ?? sessionUnitId,
      'ownerId': response['ownerId'] ?? ownerId,
    });
  }

  Future<PagedResultDto<SessionSummary>> getChanges({
    required int ownerId,
    required int minTicks,
    int maxResultCount = 99,
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/api/chat/session-unit-cache/changes',
      query: <String, Object?>{
        'ownerId': ownerId,
        'minTicks': minTicks,
        'maxResultCount': maxResultCount,
      },
    );
    return PagedResultDto<SessionSummary>.fromJson(
      response,
      SessionSummary.fromJson,
    );
  }

  Future<PagedResultDto<LoggedInDevice>> getDevices() async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/api/chat/device/by-current-user',
    );
    return PagedResultDto<LoggedInDevice>.fromJson(
      response,
      LoggedInDevice.fromJson,
    );
  }

  Future<PagedResultDto<LoggedInDevice>> getOnlineDevices() async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/api/chat/online/by-current-user',
    );
    return PagedResultDto<LoggedInDevice>.fromJson(
      response,
      LoggedInDevice.fromJson,
    );
  }

  Future<void> abortOnlineConnections({
    required List<String> connectionIds,
    required String reason,
  }) => _apiClient.post<Map<String, dynamic>>(
    '/api/chat/online/abort',
    data: <String, Object?>{
      'connectionIdList': connectionIds,
      'reason': reason,
    },
  );

  Future<void> setTopping(String sessionUnitId, bool value) async {
    await _apiClient.post<Map<String, dynamic>>(
      '/api/chat/session-unit-setting/set-topping/$sessionUnitId',
      query: <String, Object?>{'isTopping': value},
    );
  }

  Future<void> setImmersed(String sessionUnitId, bool value) async {
    await _apiClient.post<Map<String, dynamic>>(
      '/api/chat/session-unit-setting/set-immersed/$sessionUnitId',
      query: <String, Object?>{'isImmersed': value},
    );
  }

  Future<void> clearMessages(String sessionUnitId) async {
    await _apiClient.post<Map<String, dynamic>>(
      '/api/chat/session-unit-setting/clear-message/$sessionUnitId',
    );
  }
}
