import 'package:flutter/foundation.dart';

import '../data/models/chat_member.dart';
import '../data/repositories/chat_settings_repository.dart';

class MemberListController extends ChangeNotifier {
  MemberListController(
    this._repository, {
    required this.ownerId,
    required this.sessionUnitId,
    this.initialTotalCount = 0,
  }) : totalCount = initialTotalCount;

  final ChatSettingsRepository _repository;
  final int ownerId;
  final String sessionUnitId;
  final int initialTotalCount;
  final List<ChatMember> members = <ChatMember>[];
  bool loading = false;
  bool hasMore = true;
  int totalCount;
  String keyword = '';
  Object? error;

  Future<void> initialize() async {
    // 1. 先加载本地数据，立即渲染呈现（0 延迟秒开）
    try {
      final localPage = await _repository.loadLocalMembers(
        ownerId: ownerId,
        sessionUnitId: sessionUnitId,
        limit: 30,
        keyword: keyword,
      );
      if (localPage.items.isNotEmpty) {
        members
          ..clear()
          ..addAll(localPage.items);
        if (localPage.totalCount != null && localPage.totalCount! > 0) {
          totalCount = localPage.totalCount!;
        } else if (totalCount == 0) {
          totalCount = members.length;
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[MemberListController] loadLocalMembers error: $e');
    }

    // 2. 紧接着无缝向服务端拉取第一页最新数据校准
    await _loadRemoteFirstPage();
  }

  Future<void> refresh() async {
    if (loading) return;
    await _loadRemoteFirstPage();
  }

  Future<void> search(String value) async {
    keyword = value.trim();
    members.clear();
    hasMore = true;
    await _loadRemoteFirstPage();
  }

  Future<void> _loadRemoteFirstPage() async {
    if (loading) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final page = await _repository.loadRemoteMembers(
        ownerId: ownerId,
        sessionUnitId: sessionUnitId,
        limit: 30,
        keyword: keyword,
      );
      members
        ..clear()
        ..addAll(page.items);
      hasMore = page.hasMore;
      if (page.totalCount != null && page.totalCount! > 0) {
        totalCount = page.totalCount!;
      } else if (totalCount == 0) {
        totalCount = members.length;
      }
    } catch (exception) {
      error = exception;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (loading || !hasMore) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final last = members.isEmpty ? null : members.last;
      final page = await _repository.loadRemoteMembers(
        ownerId: ownerId,
        sessionUnitId: sessionUnitId,
        cursorScore: last?.score,
        cursorId: last?.id,
        skipCount: (last?.score == null) ? members.length : 0,
        limit: 30,
        keyword: keyword,
      );
      if (page.items.isEmpty) {
        hasMore = false;
      } else {
        final existingIds = members.map((e) => e.id).toSet();
        final newItems =
            page.items.where((e) => !existingIds.contains(e.id)).toList();
        if (newItems.isEmpty) {
          hasMore = false;
        } else {
          members.addAll(newItems);
          hasMore = page.hasMore;
        }
      }
      if (page.totalCount != null && page.totalCount! > totalCount) {
        totalCount = page.totalCount!;
      }
      if (members.length > totalCount) {
        totalCount = members.length;
      }
    } catch (exception) {
      error = exception;
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
