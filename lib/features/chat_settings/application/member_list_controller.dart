import 'package:flutter/foundation.dart';

import '../data/models/chat_member.dart';
import '../data/repositories/chat_settings_repository.dart';

class MemberListController extends ChangeNotifier {
  MemberListController(
    this._repository, {
    required this.ownerId,
    required this.sessionUnitId,
  });
  final ChatSettingsRepository _repository;
  final int ownerId;
  final String sessionUnitId;
  final List<ChatMember> members = <ChatMember>[];
  bool loading = false;
  bool hasMore = true;
  int totalCount = 0;
  String keyword = '';
  Object? error;

  Future<void> initialize() => loadMore();

  Future<void> refresh() async {
    if (loading) return;
    members.clear();
    hasMore = true;
    totalCount = 0;
    await loadMore(forceRemote: true);
  }

  Future<void> search(String value) async {
    keyword = value.trim();
    members.clear();
    hasMore = true;
    await loadMore(forceRemote: keyword.isNotEmpty);
  }

  Future<void> loadMore({bool forceRemote = false}) async {
    if (loading || !hasMore) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final last = members.isEmpty ? null : members.last;
      final page = await _repository.loadMembers(
        ownerId: ownerId,
        sessionUnitId: sessionUnitId,
        cursorScore: last?.score,
        cursorId: last?.id,
        limit: 30,
        keyword: keyword,
        forceRemote: forceRemote,
      );
      final ids = members.map((item) => item.id).toSet();
      members.addAll(page.items.where((item) => ids.add(item.id)));
      hasMore = page.hasMore;
      totalCount = page.totalCount ?? totalCount;
    } catch (exception) {
      error = exception;
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
