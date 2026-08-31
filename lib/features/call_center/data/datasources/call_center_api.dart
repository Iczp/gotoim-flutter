import '../../../../core/network/api_client.dart';
import '../../../session/data/models/paged_result_dto.dart';
import '../models/transfer_target.dart';

class CallCenterApi {
  CallCenterApi(this._apiClient);

  final ApiClient _apiClient;

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
