import '../../../../core/network/api_client.dart';

/// AI run endpoints associated with chat sessions.
class AiApi {
  AiApi(this._apiClient);

  final ApiClient _apiClient;

  Future<Map<String, dynamic>?> getActiveAiRun({
    required String sessionUnitId,
  }) async {
    // A 204 response is the normal "no active run" response. Request dynamic
    // here so null is represented as null rather than failing a Map cast.
    final response = await _apiClient.get<dynamic>(
      '/api/chat/ai/active/$sessionUnitId',
    );
    if (response is! Map || response.isEmpty) return null;
    return Map<String, dynamic>.from(response);
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

  /// Dispatches cancellation for an active AI run so the backend and LLM stop generating.
  Future<void> cancelAiRun({
    required String runId,
    String? sessionUnitId,
    int? sourceMessageId,
  }) async {
    final payload = <String, dynamic>{
      'runId': runId,
      if (sessionUnitId != null && sessionUnitId.isNotEmpty)
        'sessionUnitId': sessionUnitId,
      if (sourceMessageId != null) 'sourceMessageId': sourceMessageId,
    };
    try {
      await _apiClient.post<dynamic>(
        '/api/chat/ai/cancel',
        data: payload,
      );
    } catch (_) {
      // Best-effort fallback to direct ID route
      try {
        await _apiClient.post<dynamic>(
          '/api/chat/ai/cancel/$runId',
          data: payload,
        );
      } catch (_) {
        // Suppress network cancellation errors
      }
    }
  }
}

