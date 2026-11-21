import '../../../../core/network/api_client.dart';
import '../../../session/data/models/paged_result_dto.dart';
import '../models/transfer_target.dart';

class CallCenterApi {
  CallCenterApi(this._apiClient);

  final ApiClient _apiClient;

  Future<Map<String, dynamic>> getConfiguration(int shopKeeperId) =>
      _apiClient.get<Map<String, dynamic>>(
        '/api/chat/call-center/configuration',
        query: {'shopKeeperId': shopKeeperId},
      );

  Future<Map<String, dynamic>> updateConfiguration(
    int shopKeeperId,
    Map<String, Object?> input,
  ) => _apiClient.post<Map<String, dynamic>>(
    '/api/chat/call-center/update-configuration',
    query: {'shopKeeperId': shopKeeperId},
    data: input,
  );

  Future<Map<String, dynamic>> getActiveCounts(int shopKeeperId) =>
      _apiClient.get<Map<String, dynamic>>(
        '/api/chat/call-center/active-counts',
        query: {'shopKeeperId': shopKeeperId},
      );

  Future<List<dynamic>> getAgents(int shopKeeperId) =>
      _apiClient.get<List<dynamic>>(
        '/api/chat/call-center/agents',
        query: {'shopKeeperId': shopKeeperId},
      );

  Future<int> drainQueue(int shopKeeperId) => _apiClient.post<int>(
    '/api/chat/call-center/drain-queue',
    query: {'shopKeeperId': shopKeeperId},
  );

  Future<Map<String, dynamic>> getAssignments({
    required int shopKeeperId,
    required int status,
    String? afterQueuedAt,
    String? afterId,
  }) => _apiClient.get<Map<String, dynamic>>(
    '/api/chat/call-center/assignments',
    query: {
      'shopKeeperId': shopKeeperId,
      'status': status,
      'afterQueuedAt': afterQueuedAt,
      'afterId': afterId,
      'maxResultCount': 30,
    },
  );

  Future<void> cancelQueue(String sessionId) => _apiClient.post<dynamic>(
    '/api/chat/call-center/cancel-queue',
    query: {'sessionId': sessionId},
  );

  Future<void> transferAssignment(String sessionId, int destinationId) =>
      _apiClient.post<dynamic>(
        '/api/chat/call-center/transfer-assignment',
        query: {'sessionId': sessionId, 'destinationId': destinationId},
      );

  Future<PagedResultDto<TransferTarget>> getTransferTargets({
    required int shopKeeperId,
    required String keyword,
    required int skipCount,
    int maxResultCount = 30,
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/api/chat/shop-waiter',
      query: <String, Object?>{
        'ShopKeeperId': shopKeeperId,
        'IsContainsShopKeeper': true,
        'Keyword': keyword.isEmpty ? null : keyword,
        'SkipCount': skipCount,
        'MaxResultCount': maxResultCount,
      },
    );
    return PagedResultDto<TransferTarget>.fromJson(
      response,
      TransferTarget.fromJson,
    );
  }

  Future<void> transferTo({
    required String sessionUnitId,
    required int destinationId,
  }) => _apiClient.post<Map<String, dynamic>>(
    '/api/chat/call-center/transfer-to',
    query: <String, Object?>{
      'sessionUnitId': sessionUnitId,
      'destinationId': destinationId,
    },
  );
}
