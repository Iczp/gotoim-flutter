import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../app/application_providers.dart';
import '../data/datasources/session_dao.dart';
import '../data/datasources/session_unit_api.dart';
import '../data/models/session_summary.dart';
import '../data/repositories/session_repository.dart';

final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  return SessionRepository(
    api: SessionUnitApi(ref.watch(apiClientProvider)),
    dao: SessionDao(ref.watch(unifiedDatabaseProvider)),
  );
});

final sessionListControllerProvider =
    ChangeNotifierProvider<SessionListController>((ref) {
      return SessionListController(ref.watch(sessionRepositoryProvider));
    });

class SessionListController extends ChangeNotifier {
  SessionListController(this._repository);

  final SessionRepository _repository;
  List<SessionSummary> _sessions = const <SessionSummary>[];
  bool _isLoading = false;
  bool _isSyncing = false;
  Object? _error;
  int? _ownerId;

  List<SessionSummary> get sessions => _sessions;
  bool get isLoading => _isLoading;
  bool get isSyncing => _isSyncing;
  Object? get error => _error;

  /// Displays Drift data first, then refreshes it from the server.
  Future<void> load() async {
    if (_isLoading) return;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _sessions = await _repository.loadCached();
      notifyListeners();
      _ownerId ??= await _repository.resolveCurrentOwnerId();
      await sync();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> sync() async {
    if (_isSyncing) return;
    _isSyncing = true;
    _error = null;
    notifyListeners();
    try {
      _ownerId ??= await _repository.resolveCurrentOwnerId();
      _sessions = await _repository.sync(ownerId: _ownerId);
    } catch (error) {
      _error = error;
      debugPrint('Session list sync failed: $error');
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }
}
