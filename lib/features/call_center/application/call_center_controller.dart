import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/application_providers.dart';
import '../data/datasources/call_center_api.dart';
import '../data/models/transfer_target.dart';
import '../data/repositories/call_center_repository.dart';

final callCenterRepositoryProvider = Provider<CallCenterRepository>(
  (ref) => CallCenterRepository(CallCenterApi(ref.watch(apiClientProvider))),
);

class CallCenterController extends ChangeNotifier {
  CallCenterController({
    required CallCenterRepository repository,
    required this.shopKeeperId,
    required this.sourceOwnerId,
    required this.sessionUnitId,
  }) : _repository = repository;

  static const pageSize = 30;
  final CallCenterRepository _repository;
  final int shopKeeperId;
  final int? sourceOwnerId;
  final String sessionUnitId;
  final List<TransferTarget> _targets = <TransferTarget>[];
  String _keyword = '';
  int _generation = 0;
  int _remoteSkipCount = 0;
  bool isLoading = false;
  bool isSubmitting = false;
  bool hasMore = true;
  Object? error;

  List<TransferTarget> get targets => List.unmodifiable(_targets);

  Future<void> initialize() => _load(reset: true);

  Future<void> updateKeyword(String value) {
    final keyword = value.trim();
    if (keyword == _keyword) return Future<void>.value();
    _keyword = keyword;
    return _load(reset: true);
  }

  Future<void> loadMore() => _load(reset: false);
  Future<void> refresh() => _load(reset: true);

  Future<void> _load({required bool reset}) async {
    if (!reset && (isLoading || !hasMore)) return;
    final generation = ++_generation;
    isLoading = true;
    error = null;
    if (reset) {
      _targets.clear();
      _remoteSkipCount = 0;
      hasMore = true;
    }
    notifyListeners();
    try {
      final page = await _repository.loadTransferTargets(
        shopKeeperId: shopKeeperId,
        keyword: _keyword,
        skipCount: _remoteSkipCount,
      );
      if (generation != _generation) return;
      final known = _targets.map((target) => target.id).toSet();
      _targets.addAll(
        page.items.where(
          (target) => target.id != sourceOwnerId && known.add(target.id),
        ),
      );
      _remoteSkipCount += page.items.length;
      hasMore = page.hasMore;
      debugPrint(
        '[transferTargets][remote] shopKeeperId=$shopKeeperId '
        'skip=$_remoteSkipCount added=${page.items.length} hasMore=$hasMore',
      );
    } catch (exception) {
      if (generation == _generation) {
        error = exception;
        debugPrint(
          '[transferTargets][failed] shopKeeperId=$shopKeeperId error=$exception',
        );
      }
    } finally {
      if (generation == _generation) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> transferTo(TransferTarget target) async {
    if (isSubmitting) return;
    isSubmitting = true;
    error = null;
    notifyListeners();
    try {
      await _repository.transferTo(
        sessionUnitId: sessionUnitId,
        destinationId: target.id,
      );
      debugPrint(
        '[transfer][success] session=$sessionUnitId destination=${target.id}',
      );
    } catch (exception) {
      error = exception;
      debugPrint(
        '[transfer][failed] session=$sessionUnitId destination=${target.id} error=$exception',
      );
      rethrow;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }
}
