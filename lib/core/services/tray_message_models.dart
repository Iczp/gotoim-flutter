import 'package:flutter/foundation.dart';

/// 托盘会话项模型 (二级未读好友/群)
@immutable
class TraySessionItem {
  const TraySessionItem({
    required this.sessionUnitId,
    required this.targetName,
    required this.lastMessageText,
    required this.unreadCount,
    this.avatarUrl,
    this.lastMessageTime,
    this.isGroup = false,
  });

  /// 会话单元 ID
  final String sessionUnitId;

  /// 好友名称 / 群名称
  final String targetName;

  /// 最新消息摘要文本
  final String lastMessageText;

  /// 当前会话未读数
  final int unreadCount;

  /// 头像地址
  final String? avatarUrl;

  /// 最后一条消息时间
  final DateTime? lastMessageTime;

  /// 是否为群聊
  final bool isGroup;

  TraySessionItem copyWith({
    String? sessionUnitId,
    String? targetName,
    String? lastMessageText,
    int? unreadCount,
    String? avatarUrl,
    DateTime? lastMessageTime,
    bool? isGroup,
  }) {
    return TraySessionItem(
      sessionUnitId: sessionUnitId ?? this.sessionUnitId,
      targetName: targetName ?? this.targetName,
      lastMessageText: lastMessageText ?? this.lastMessageText,
      unreadCount: unreadCount ?? this.unreadCount,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      isGroup: isGroup ?? this.isGroup,
    );
  }
}

/// 托盘聊天对象分组模型 (一级分组：聊天对象 1 包含头像与新消息总数量)
@immutable
class TrayOwnerGroup {
  const TrayOwnerGroup({
    required this.ownerId,
    required this.ownerName,
    required this.totalUnread,
    required this.sessions,
    this.avatarUrl,
    this.isCurrent = false,
    this.roleTitle,
  });

  /// 聊天对象/身份 ID (ChatObjectId / OwnerId)
  final int ownerId;

  /// 聊天对象昵称 / 身份名
  final String ownerName;

  /// 该聊天对象头像
  final String? avatarUrl;

  /// 是否为当前正在使用的活跃身份
  final bool isCurrent;

  /// 身份标签或职位角色
  final String? roleTitle;

  /// 该聊天对象下的新消息总数量 (即：聊天对象1包含头像 5-新消息总数量)
  final int totalUnread;

  /// 该聊天对象下有未读消息的会话列表
  final List<TraySessionItem> sessions;

  TrayOwnerGroup copyWith({
    int? ownerId,
    String? ownerName,
    String? avatarUrl,
    bool? isCurrent,
    String? roleTitle,
    int? totalUnread,
    List<TraySessionItem>? sessions,
  }) {
    return TrayOwnerGroup(
      ownerId: ownerId ?? this.ownerId,
      ownerName: ownerName ?? this.ownerName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isCurrent: isCurrent ?? this.isCurrent,
      roleTitle: roleTitle ?? this.roleTitle,
      totalUnread: totalUnread ?? this.totalUnread,
      sessions: sessions ?? this.sessions,
    );
  }
}

/// 托盘聚合未读状态
@immutable
class TrayGroupedUnreadState {
  const TrayGroupedUnreadState({
    required this.totalUnread,
    required this.groups,
  });

  /// 全局未读总数（所有聊天对象未读数总和）
  final int totalUnread;

  /// 按聊天对象分组的未读列表
  final List<TrayOwnerGroup> groups;

  static const empty = TrayGroupedUnreadState(totalUnread: 0, groups: []);

  Map<String, dynamic> toJson() => {
    'totalUnread': totalUnread,
    'groups': [
      for (final g in groups)
        {
          'ownerId': g.ownerId,
          'ownerName': g.ownerName,
          'totalUnread': g.totalUnread,
          'isCurrent': g.isCurrent,
          'avatarUrl': g.avatarUrl,
          'roleTitle': g.roleTitle,
          'sessions': [
            for (final s in g.sessions)
              {
                'sessionUnitId': s.sessionUnitId,
                'targetName': s.targetName,
                'lastMessageText': s.lastMessageText,
                'unreadCount': s.unreadCount,
                'avatarUrl': s.avatarUrl,
                'lastMessageTime': s.lastMessageTime?.toIso8601String(),
                'isGroup': s.isGroup,
              },
          ],
        },
    ],
  };

  factory TrayGroupedUnreadState.fromJson(Map map) => TrayGroupedUnreadState(
    totalUnread: (map['totalUnread'] as num?)?.toInt() ?? 0,
    groups: [
      for (final g in map['groups'] as List? ?? const [])
        TrayOwnerGroup(
          ownerId: (g['ownerId'] as num).toInt(),
          ownerName: g['ownerName'] as String,
          totalUnread: (g['totalUnread'] as num).toInt(),
          isCurrent: g['isCurrent'] == true,
          avatarUrl: g['avatarUrl'] as String?,
          roleTitle: g['roleTitle'] as String?,
          sessions: [
            for (final s in g['sessions'] as List? ?? const [])
              TraySessionItem(
                sessionUnitId: s['sessionUnitId'] as String,
                targetName: s['targetName'] as String,
                lastMessageText: s['lastMessageText'] as String,
                unreadCount: (s['unreadCount'] as num).toInt(),
                avatarUrl: s['avatarUrl'] as String?,
                isGroup: s['isGroup'] == true,
                lastMessageTime: DateTime.tryParse(
                  s['lastMessageTime']?.toString() ?? '',
                ),
              ),
          ],
        ),
    ],
  );

  TrayGroupedUnreadState copyWith({
    int? totalUnread,
    List<TrayOwnerGroup>? groups,
  }) {
    return TrayGroupedUnreadState(
      totalUnread: totalUnread ?? this.totalUnread,
      groups: groups ?? this.groups,
    );
  }
}
