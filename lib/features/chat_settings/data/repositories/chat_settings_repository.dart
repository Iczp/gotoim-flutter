import 'package:flutter/foundation.dart';

import '../datasources/chat_member_api.dart';
import '../datasources/chat_member_dao.dart';
import '../models/chat_member.dart';

class ChatSettingsRepository {
  ChatSettingsRepository({
    required ChatMemberApi api,
    required ChatMemberDao dao,
  }) : _api = api,
       _dao = dao;

  final ChatMemberApi _api;
  final ChatMemberDao _dao;

  Future<MemberPage> loadMembers({
    required int ownerId,
    required String sessionUnitId,
    int? cursorScore,
    String? cursorId,
    int limit = 30,
    String keyword = '',
    bool forceRemote = false,
  }) async {
    var local = <ChatMember>[];
    if (!forceRemote) {
      local = await _dao.readPage(
        ownerId: ownerId,
        sessionUnitId: sessionUnitId,
        cursorScore: cursorScore,
        cursorId: cursorId,
        limit: limit,
        keyword: keyword,
      );
      debugPrint(
        '[loadMembers][local] session=$sessionUnitId requested=$limit '
        'added=${local.length}',
      );
      if (local.length >= limit) return MemberPage(local, true, null);
      if (await _dao.isLoadedAll(sessionUnitId)) {
        return MemberPage(local, false, null);
      }
    }

    final last = local.isEmpty ? null : local.last;
    final remote = await _api.getMembers(
      sessionUnitId: sessionUnitId,
      limit: limit - local.length,
      maxScore: last?.score ?? cursorScore,
      cursorId: last?.id ?? cursorId,
      keyword: keyword,
    );
    await _dao.upsertAll(ownerId, sessionUnitId, remote.items);
    final hasMore = remote.items.length >= limit - local.length;
    await _dao.updateState(
      sessionUnitId,
      totalCount: remote.totalCount,
      loadedAll: !hasMore,
    );
    debugPrint(
      '[loadMembers][remote] session=$sessionUnitId received=${remote.items.length} '
      'persisted=${remote.items.length} total=${remote.totalCount} hasMore=$hasMore',
    );
    final merged =
        <String, ChatMember>{
          for (final item in local) item.id: item,
          for (final item in remote.items) item.id: item,
        }.values.toList();
    return MemberPage(merged, hasMore, remote.totalCount);
  }

  Future<void> setTopping(String id, bool value) async {
    await _api.setTopping(id, value);
  }

  Future<void> setImmersed(String id, bool value) async {
    await _api.setImmersed(id, value);
  }

  Future<void> clearMessages(int ownerId, String id) async {
    await _api.clearMessages(id);
    await _dao.clearMessages(ownerId, id);
  }
}

class MemberPage {
  const MemberPage(this.items, this.hasMore, this.totalCount);
  final List<ChatMember> items;
  final bool hasMore;
  final int? totalCount;
}
