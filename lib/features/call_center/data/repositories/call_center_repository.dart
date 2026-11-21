import '../datasources/call_center_api.dart';
import '../models/transfer_target.dart';

class TransferTargetPage {
  const TransferTargetPage({required this.items, required this.hasMore});
  final List<TransferTarget> items;
  final bool hasMore;
}

class CallCenterRepository {
  CallCenterRepository(this._api);
  final CallCenterApi _api;

  Future<Map<String, dynamic>> getConfiguration(int shopKeeperId) =>
      _api.getConfiguration(shopKeeperId);

  Future<Map<String, dynamic>> updateConfiguration(
    int shopKeeperId,
    Map<String, Object?> input,
  ) => _api.updateConfiguration(shopKeeperId, input);

  Future<Map<String, dynamic>> getActiveCounts(int shopKeeperId) =>
      _api.getActiveCounts(shopKeeperId);

  Future<List<Map<String, dynamic>>> getAgents(int shopKeeperId) async =>
      (await _api.getAgents(
        shopKeeperId,
      )).whereType<Map<String, dynamic>>().toList(growable: false);

  Future<int> drainQueue(int shopKeeperId) => _api.drainQueue(shopKeeperId);

  Future<Map<String, dynamic>> getAssignments({
    required int shopKeeperId,
    required int status,
    String? afterQueuedAt,
    String? afterId,
  }) => _api.getAssignments(
    shopKeeperId: shopKeeperId,
    status: status,
    afterQueuedAt: afterQueuedAt,
    afterId: afterId,
  );

  Future<void> cancelQueue(String sessionId) => _api.cancelQueue(sessionId);

  Future<void> transferAssignment(String sessionId, int destinationId) =>
      _api.transferAssignment(sessionId, destinationId);

  Future<TransferTargetPage> loadTransferTargets({
    required int shopKeeperId,
    required String keyword,
    required int skipCount,
    int limit = 30,
  }) async {
    final result = await _api.getTransferTargets(
      shopKeeperId: shopKeeperId,
      keyword: keyword,
      skipCount: skipCount,
      maxResultCount: limit,
    );
    return TransferTargetPage(
      items: result.items
          .where((target) => target.id > 0)
          .toList(growable: false),
      hasMore: skipCount + result.items.length < result.totalCount,
    );
  }

  Future<void> transferTo({
    required String sessionUnitId,
    required int destinationId,
  }) => _api.transferTo(
    sessionUnitId: sessionUnitId,
    destinationId: destinationId,
  );
}
