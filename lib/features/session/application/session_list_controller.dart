import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../app/application_providers.dart';
import '../data/datasources/session_dao.dart';
import '../data/datasources/session_unit_api.dart';
import '../data/models/chat_owner.dart';
import '../data/models/session_summary.dart';
import '../data/repositories/session_repository.dart';

final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => SessionRepository(
    api: SessionUnitApi(ref.watch(apiClientProvider)),
    dao: SessionDao(ref.watch(unifiedDatabaseProvider)),
  ),
);

final sessionListControllerProvider =
    ChangeNotifierProvider<SessionListController>(
      (ref) => SessionListController(ref.watch(sessionRepositoryProvider)),
    );

class SessionListController extends ChangeNotifier {
  SessionListController(this._repository);
  static const pageSize = 50;
  final SessionRepository _repository;
  final List<SessionSummary> _sessions = [];
  List<ChatOwner> _owners = const [];
  ChatOwner? _currentOwner;
  bool _isLoading = false;
  bool _isRefreshing = false;
  bool _hasMore = true;
  Object? _error;

  List<SessionSummary> get sessions => List.unmodifiable(_sessions);
  List<ChatOwner> get owners => _owners;
  ChatOwner? get currentOwner => _currentOwner;
  bool get isLoading => _isLoading;
  bool get isRefreshing => _isRefreshing;
  bool get hasMore => _hasMore;
  Object? get error => _error;

  Future<void> initialize() async {
    if (_isLoading || _currentOwner != null) return;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _owners = await _repository.loadOwners();
      if (_owners.isEmpty) throw StateError('当前账号没有可用的聊天对象');
      final savedOwnerId = await _repository.readCurrentOwnerId();
      _currentOwner = _owners.cast<ChatOwner?>().firstWhere(
        (owner) => owner?.id == savedOwnerId,
        orElse: () => _owners.first,
      );
      await _repository.saveCurrentOwnerId(_currentOwner!.id);
      await _loadNextPageInternal(reset: true);
    } catch (error) {
      _error = error;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> selectOwner(ChatOwner owner) async {
    if (_currentOwner?.id == owner.id) return;
    _currentOwner = owner;
    await _repository.saveCurrentOwnerId(owner.id);
    _sessions.clear();
    _hasMore = true;
    _error = null;
    notifyListeners();
    await loadNextPage();
  }

  Future<void> loadNextPage() async {
    if (_isLoading || !_hasMore || _currentOwner == null) return;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _loadNextPageInternal();
    } catch (error) {
      _error = error;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshChanges() async {
    final owner = _currentOwner;
    if (_isRefreshing || owner == null) return;
    _isRefreshing = true;
    _error = null;
    notifyListeners();
    try {
      await _repository.loadChanges(ownerId: owner.id);
      final local = await _repository.loadLocalFriends(
        ownerId: owner.id,
        limit: pageSize,
      );
      _sessions
        ..clear()
        ..addAll(local);
    } catch (error) {
      _error = error;
      rethrow;
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }

  Future<void> _loadNextPageInternal({bool reset = false}) async {
    final owner = _currentOwner!;
    final last = !reset && _sessions.isNotEmpty ? _sessions.last : null;
    final result = await _repository.loadFriends(
      ownerId: owner.id,
      cursor:
          last == null ? null : SessionCursor(id: last.id, score: last.score),
      limit: pageSize,
    );
    if (reset) _sessions.clear();
    final known = _sessions.map((item) => item.id).toSet();
    _sessions.addAll(result.items.where((item) => known.add(item.id)));
    _hasMore = result.hasMore;
  }
}
