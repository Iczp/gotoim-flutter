import '../../../../core/network/api_client.dart';

/// AI run endpoints associated with chat sessions.
class AiApi {
  AiApi(this._apiClient);

  final ApiClient _apiClient;

  Future<Map<String, dynamic>?> getActiveAiRun({
    required String sessionUnitId,
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/api/chat/ai/active/$sessionUnitId',
    );
    return response.isEmpty ? null : response;
  }

  /// Returns active runs for virtual-list items the current user may access.
  /// The server binds repeated `SessionUnitIds` query values.
  Future<List<Map<String, dynamic>>> getActiveAiRuns({
    required Iterable<String> sessionUnitIds,
  }) async {
    final uniqueSessionUnitIds = sessionUnitIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (uniqueSessionUnitIds.isEmpty) return const <Map<String, dynamic>>[];
    final response = await _apiClient.get<List<dynamic>>(
      '/api/chat/ai/active-batch',
      query: <String, Object?>{'SessionUnitIds': uniqueSessionUnitIds},
    );
    return response
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> getRecentAiRuns({
    required String sessionUnitId,
    int maxResultCount = 20,
  }) async {
    final response = await _apiClient.get<List<dynamic>>(
      '/api/chat/ai/recent/$sessionUnitId',
      query: <String, Object?>{'maxResultCount': maxResultCount},
    );
    return response
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }
}
