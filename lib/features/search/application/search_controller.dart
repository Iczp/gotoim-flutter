import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../session/application/session_list_controller.dart';
import '../data/search_repository.dart';
import '../domain/search_models.dart';

final globalSearchControllerProvider =
    ChangeNotifierProvider.autoDispose<GlobalSearchController>((ref) {
  final repository = ref.watch(searchRepositoryProvider);
  return GlobalSearchController(repository: repository, ref: ref);
});

class GlobalSearchController extends ChangeNotifier {
  GlobalSearchController({
    required SearchRepository repository,
    required Ref ref,
  })  : _repository = repository,
        _ref = ref {
    loadHistory();
  }

  final SearchRepository _repository;
  final Ref _ref;
  Timer? _remoteDebounceTimer;

  SearchResultState _state = const SearchResultState();
  SearchResultState get state => _state;

  int? get _currentOwnerId {
    try {
      final sessionController = _ref.read(sessionListControllerProvider);
      return sessionController.currentOwner?.id;
    } catch (_) {
      return null;
    }
  }

  Future<void> loadHistory() async {
    try {
      final history = await _repository.getSearchHistory();
      _state = _state.copyWith(history: history);
      notifyListeners();
    } catch (_) {}
  }

  void onQueryChanged(String text) {
    final query = text.trim();
    _remoteDebounceTimer?.cancel();

    if (query.isEmpty) {
      _state = _state.copyWith(
        keyword: '',
        isLocalLoading: false,
        isRemoteLoading: false,
        localContacts: const <SearchContactItem>[],
        localMessages: const <SearchMessageItem>[],
        remoteContacts: const <SearchRemoteContactItem>[],
      );
      notifyListeners();
      return;
    }

    _state = _state.copyWith(keyword: text);
    notifyListeners();

    // 1. 离线优先：立即执行本地检索
    _searchLocal(query);

    // 2. 防抖 350ms 触发线上预览搜索
    _remoteDebounceTimer = Timer(const Duration(milliseconds: 350), () {
      _searchRemote(query);
    });
  }

  Future<void> _searchLocal(String query) async {
    final ownerId = _currentOwnerId ?? 0;
    _state = _state.copyWith(isLocalLoading: true);
    notifyListeners();

    try {
      final contactsFuture = _repository.searchLocalContacts(
        ownerId: ownerId,
        keyword: query,
      );
      final messagesFuture = _repository.searchLocalMessages(
        ownerId: ownerId,
        keyword: query,
      );

      final results = await Future.wait([contactsFuture, messagesFuture]);
      if (_state.keyword.trim() != query) return;

      _state = _state.copyWith(
        isLocalLoading: false,
        localContacts: results[0] as List<SearchContactItem>,
        localMessages: results[1] as List<SearchMessageItem>,
      );
      notifyListeners();
    } catch (e) {
      if (_state.keyword.trim() == query) {
        _state = _state.copyWith(isLocalLoading: false);
        notifyListeners();
      }
    }
  }

  Future<void> _searchRemote(String query) async {
    final ownerId = _currentOwnerId ?? 0;
    _state = _state.copyWith(isRemoteLoading: true);
    notifyListeners();

    try {
      final remotes = await _repository.searchRemoteContacts(
        ownerId: ownerId,
        keyword: query,
      );
      if (_state.keyword.trim() != query) return;

      _state = _state.copyWith(
        isRemoteLoading: false,
        remoteContacts: remotes,
      );
      notifyListeners();
    } catch (_) {
      if (_state.keyword.trim() == query) {
        _state = _state.copyWith(isRemoteLoading: false);
        notifyListeners();
      }
    }
  }

  Future<void> recordKeyword(String keyword) async {
    final term = keyword.trim();
    if (term.isEmpty) return;
    try {
      final updated = await _repository.addSearchHistory(term);
      _state = _state.copyWith(history: updated);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> deleteHistoryItem(String keyword) async {
    try {
      final updated = await _repository.deleteSearchHistory(keyword);
      _state = _state.copyWith(history: updated);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> clearAllHistory() async {
    try {
      await _repository.clearSearchHistory();
      _state = _state.copyWith(history: const <String>[]);
      notifyListeners();
    } catch (_) {}
  }

  @override
  void dispose() {
    _remoteDebounceTimer?.cancel();
    super.dispose();
  }
}
