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

  Future<PagedResultDto<SessionSummary>> getFriends({
    required int ownerId,
    int maxResultCount = 100,
    int? maxScore,
    String? cursorId,
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/api/chat/session-unit-cache/friends',
      query: <String, Object?>{
        'ownerId': ownerId,
        'maxResultCount': maxResultCount,
        if (maxScore != null) 'maxScore': maxScore,
        if (cursorId != null) 'cursorId': cursorId,
      },
    );
    return PagedResultDto<SessionSummary>.fromJson(
      response,
      SessionSummary.fromJson,
    );
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
}
