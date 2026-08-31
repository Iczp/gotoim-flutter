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
