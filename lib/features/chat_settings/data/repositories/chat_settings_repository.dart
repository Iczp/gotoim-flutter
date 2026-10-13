import 'package:flutter/foundation.dart';

import '../../../../core/network/api_client.dart';
import '../datasources/chat_member_api.dart';
import '../datasources/chat_member_dao.dart';
import '../models/chat_member.dart';
import '../../../session/data/session_change_bus.dart';

class ChatSettingsRepository {
  ChatSettingsRepository({
    required ChatMemberApi api,
    required ChatMemberDao dao,
    SessionChangeBus? sessionChangeBus,
  }) : _api = api,
       _dao = dao,
       _sessionChangeBus = sessionChangeBus;

  final ChatMemberApi _api;
  final ChatMemberDao _dao;
  final SessionChangeBus? _sessionChangeBus;

  /// 读取本地缓存的成员列表与总数（0 延迟即时呈现）
  Future<MemberPage> loadLocalMembers({
    required int ownerId,
    required String sessionUnitId,
    int? cursorScore,
    String? cursorId,
    int limit = 30,
    String keyword = '',
  }) async {
    final local = await _dao.readPage(
      ownerId: ownerId,
      sessionUnitId: sessionUnitId,
      cursorScore: cursorScore,
      cursorId: cursorId,
      limit: limit,
      keyword: keyword,
    );
    var count = await _dao.readMemberCount(sessionUnitId);
    if (count == null || count <= 0) {
      count = await _dao.countMembers(
        ownerId: ownerId,
        sessionUnitId: sessionUnitId,
        keyword: keyword,
      );
    }
    final isLoadedAll = await _dao.isLoadedAll(sessionUnitId);
    final hasMore = !isLoadedAll && local.length >= limit;
    final resolvedCount =
        count > 0 ? count : (local.isNotEmpty ? local.length : null);
    return MemberPage(local, hasMore, resolvedCount);
  }

  /// 从服务端拉取最新成员列表并更新本地缓存与状态
  Future<MemberPage> loadRemoteMembers({
    required int ownerId,
    required String sessionUnitId,
    int? cursorScore,
    String? cursorId,
    int limit = 30,
    int skipCount = 0,
    String keyword = '',
  }) async {
    final hasCursor = cursorScore != null || (cursorId != null && cursorId.isNotEmpty);
    final remote = await _api.getMembers(
      sessionUnitId: sessionUnitId,
      limit: limit,
      maxScore: cursorScore,
      cursorId: cursorId,
      skipCount: hasCursor ? 0 : skipCount,
      keyword: keyword,
    );

    if (remote.items.isNotEmpty) {
      await _dao.upsertAll(ownerId, sessionUnitId, remote.items);
    }

    final isFirstPage =
        cursorScore == null && cursorId == null && skipCount == 0;
    final hasMore = remote.hasMore ?? (remote.items.length >= limit);

    // 仅在无搜索、第一页请求时拿到全群权威总人数，才持久化到本地
    if (isFirstPage && keyword.isEmpty && remote.totalCount > 0) {
      await _dao.updateState(
        sessionUnitId,
        totalCount: remote.totalCount,
        loadedAll: !hasMore,
      );
    } else if (!hasMore && keyword.isEmpty) {
      await _dao.updateState(
        sessionUnitId,
        loadedAll: true,
      );
    }

    debugPrint(
      '[loadRemoteMembers] session=$sessionUnitId count=${remote.items.length} '
      'total=${remote.totalCount} hasMore=$hasMore',
    );
    return MemberPage(remote.items, hasMore, remote.totalCount);
  }

  /// 兼容旧调用入口
  Future<MemberPage> loadMembers({
    required int ownerId,
    required String sessionUnitId,
    int? cursorScore,
    String? cursorId,
    int limit = 30,
    String keyword = '',
    bool forceRemote = false,
  }) async {
    if (!forceRemote) {
      final localPage = await loadLocalMembers(
        ownerId: ownerId,
        sessionUnitId: sessionUnitId,
        cursorScore: cursorScore,
        cursorId: cursorId,
        limit: limit,
        keyword: keyword,
      );
      if (localPage.items.length >= limit) {
        return localPage;
      }
    }

    return loadRemoteMembers(
      ownerId: ownerId,
      sessionUnitId: sessionUnitId,
      cursorScore: cursorScore,
      cursorId: cursorId,
      limit: limit,
      keyword: keyword,
    );
  }

  Future<void> setTopping(String id, bool value) async {
    await _api.setTopping(id, value);
  }

  Future<void> setImmersed(String id, bool value) async {
    await _api.setImmersed(id, value);
  }

  Future<void> exitChat(String id) async {
    await _api.exitChat(id);
  }

  Future<void> unsubscribeOfficial(String id) async {
    await _api.unsubscribeOfficial(id);
  }

  Future<void> clearMessages(int ownerId, String id) async {
    await _api.clearMessages(id);
    await _dao.clearMessages(ownerId, id);
    _sessionChangeBus?.publish(ownerId: ownerId, sessionUnitId: id);
  }

  Future<void> setRename(String id, String rename) async {
    await _api.setRename(id, rename);
  }

  Future<void> setBackgroundImage(String id, MultipartUploadFile file) async {
    await _api.setBackgroundImage(id: id, file: file);
  }

  Future<void> clearBackgroundImage(String id) async {
    await _api.clearBackgroundImage(id);
  }

  Future<void> setRoomTitle(String roomId, String title) async {
    await _api.setRoomTitle(roomId, title);
  }
}

class MemberPage {
  const MemberPage(this.items, this.hasMore, this.totalCount);
  final List<ChatMember> items;
  final bool hasMore;
  final int? totalCount;
}
