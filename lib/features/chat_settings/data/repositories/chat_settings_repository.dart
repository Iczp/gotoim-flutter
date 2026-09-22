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
        'cursorScore=$cursorScore cursorId=$cursorId added=${local.length}',
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
    final requestedRemoteCount = limit - local.length;
    final hasMore =
        remote.hasMore ?? remote.items.length >= requestedRemoteCount;
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
