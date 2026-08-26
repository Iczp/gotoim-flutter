import '../../../../core/network/api_client.dart';
import '../models/paged_result_dto.dart';
import '../models/session_summary.dart';

/// ABP session-unit cache endpoints used by the conversation list.
class SessionUnitApi {
  SessionUnitApi(this._apiClient);

  final ApiClient _apiClient;

  Future<PagedResultDto<SessionSummary>> getFriends({
    int? ownerId,
    int maxResultCount = 50,
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/api/chat/session-unit-cache/friends',
      query: <String, Object?>{
        if (ownerId != null) 'ownerId': ownerId,
        'maxResultCount': maxResultCount,
      },
    );
    return PagedResultDto<SessionSummary>.fromJson(
      response,
      SessionSummary.fromJson,
    );
  }
}
