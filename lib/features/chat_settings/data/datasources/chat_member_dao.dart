import 'dart:convert';
import '../../../../core/database/unified_database.dart';
import '../../../session/data/models/session_summary_helpers.dart';
import '../models/chat_member.dart';

class ChatMemberDao {
  ChatMemberDao(this._database);
  final UnifiedDatabase _database;

  Future<List<ChatMember>> readPage({
    required int ownerId,
    required String sessionUnitId,
    int? cursorScore,
    String? cursorId,
    int limit = 50,
    String keyword = '',
  }) async => (await _database.readMemberRows(
    ownerId: ownerId,
    sessionUnitId: sessionUnitId,
    cursorScore: cursorScore,
    cursorId: cursorId,
    limit: limit,
    keyword: keyword,
  )).map(ChatMember.fromDatabaseRow).toList(growable: false);

  Future<int?> readMemberCount(String sessionUnitId) =>
      _database.readFriendMemberCount(sessionUnitId);

  Future<int> countMembers({
    required int ownerId,
    required String sessionUnitId,
    String keyword = '',
  }) => _database.countMembers(
    ownerId: ownerId,
    sessionUnitId: sessionUnitId,
    keyword: keyword,
  );

  Future<void> upsertAll(
    int ownerId,
    String sessionUnitId,
    List<ChatMember> items,
  ) => _database.upsertMemberRows(
    items.map((item) => item.toDatabaseValues(ownerId, sessionUnitId)).toList(),
  );

  Future<int> deleteMember(String sessionUnitId, String memberId) =>
      _database.deleteMemberRow(sessionUnitId: sessionUnitId, memberId: memberId);

  Future<void> demoteStaleAdmins(
    int ownerId,
    String sessionUnitId,
    Set<String> activeAdminIds,
  ) => _database.demoteStaleAdmins(
    ownerId: ownerId,
    sessionUnitId: sessionUnitId,
    activeAdminIds: activeAdminIds,
  );

  Future<void> updateState(
    String sessionUnitId, {
    int? totalCount,
    bool? loadedAll,
  }) => _database.updateFriendMemberState(
    sessionUnitId: sessionUnitId,
    memberCount: totalCount,
    loadedAll: loadedAll,
  );

  Future<bool> isLoadedAll(String sessionUnitId) =>
      _database.readFriendMembersLoadedAll(sessionUnitId);

  Future<int> clearMessages(int ownerId, String sessionUnitId) =>
      _database.resetFriendMessages(ownerId, sessionUnitId);

  /// 将消息批次中去重提取出的少量发送人顺带合并更新到本地 Members 表：
  /// 既刷新最新群名片、头像与群主/管理角色，又完整保留本地已拉取过的 organizationList / roleList。
  Future<void> piggybackSenderUnits(
    int ownerId,
    String sessionUnitId,
    List<Map<String, dynamic>> distinctSenderUnits,
  ) async {
    if (distinctSenderUnits.isEmpty) return;
    final byId = <String, Map<String, dynamic>>{};
    for (final unit in distinctSenderUnits) {
      final id = unit['id']?.toString().trim() ?? '';
      if (id.isNotEmpty) {
        byId[id] = unit;
      }
    }
    if (byId.isEmpty) return;

    final existingRawMap = await _database.readMemberRawByIds(
      byId.keys.toList(growable: false),
    );
    final mergedMembers = <ChatMember>[];
    for (final entry in byId.entries) {
      final id = entry.key;
      final incoming = entry.value;
      var mergedJson = Map<String, dynamic>.from(incoming);
      final existingRawStr = existingRawMap[id];
      if (existingRawStr != null && existingRawStr.isNotEmpty) {
        try {
          final existingJson = Map<String, dynamic>.from(
            jsonDecode(existingRawStr) as Map,
          );
          final existingSetting = asMap(existingJson['setting']);
          final incomingSetting = asMap(incoming['setting']);
          final existingOwner = asMap(existingJson['owner']);
          final incomingOwner = asMap(incoming['owner']);
          mergedJson = <String, dynamic>{
            ...existingJson,
            ...incoming,
            if (existingOwner.isNotEmpty || incomingOwner.isNotEmpty)
              'owner': <String, dynamic>{...existingOwner, ...incomingOwner},
            if (existingSetting.isNotEmpty || incomingSetting.isNotEmpty)
              'setting': <String, dynamic>{
                ...existingSetting,
                ...incomingSetting,
                if (incoming['isCreator'] != null &&
                    incomingSetting['isCreator'] == null)
                  'isCreator': incoming['isCreator'],
                if (incoming['isAdmin'] != null &&
                    incomingSetting['isAdmin'] == null)
                  'isAdmin': incoming['isAdmin'],
              },
            if (incoming['organizationList'] == null &&
                existingJson['organizationList'] != null)
              'organizationList': existingJson['organizationList'],
            if (incoming['roleList'] == null && existingJson['roleList'] != null)
              'roleList': existingJson['roleList'],
          };
        } catch (_) {
          // ignore malformed legacy raw json
        }
      }
      mergedMembers.add(ChatMember.fromJson(mergedJson));
    }
    await upsertAll(ownerId, sessionUnitId, mergedMembers);
  }
}
