import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tray_message_models.dart';
import 'tray_service.dart';

/// 托盘未读数据管理控制器 (基于 Riverpod 3 Notifier)
class TrayGroupedUnreadNotifier extends Notifier<TrayGroupedUnreadState> {
  @override
  TrayGroupedUnreadState build() {
    return TrayGroupedUnreadState.empty;
  }

  /// 加载示例测试数据 (用于诊断页或本地预览)
  void loadSampleData() {
    state = createSampleState();
    _syncWithTrayService();
  }

  static TrayGroupedUnreadState createSampleState() {
    // 初始示例数据，模拟多聊天对象与好友未读消息
    final owner1Sessions = [
      TraySessionItem(
        sessionUnitId: 'u-101',
        targetName: '李四 (前端研发)',
        lastMessageText: '前端接口联调顺利，已查收新的 Token 拦截器逻辑',
        unreadCount: 3,
        lastMessageTime: DateTime.now().subtract(const Duration(minutes: 8)),
      ),
      TraySessionItem(
        sessionUnitId: 'u-102',
        targetName: '桌面端跨平台架构组',
        lastMessageText: '王五: 系统托盘设计稿与中性黑灰色阶对齐完成',
        unreadCount: 2,
        isGroup: true,
        lastMessageTime: DateTime.now().subtract(const Duration(minutes: 20)),
      ),
    ];

    final owner2Sessions = [
      TraySessionItem(
        sessionUnitId: 'u-201',
        targetName: '华东企业客户-刘总',
        lastMessageText: '请问桌面端是否原生支持多显示器独立聊天窗口?',
        unreadCount: 2,
        lastMessageTime: DateTime.now().subtract(const Duration(hours: 1)),
      ),
    ];

    final group1 = TrayOwnerGroup(
      ownerId: 1001,
      ownerName: '张三',
      isCurrent: true,
      roleTitle: '研发部 · 架构师',
      totalUnread: 5,
      sessions: owner1Sessions,
    );

    final group2 = TrayOwnerGroup(
      ownerId: 2002,
      ownerName: 'GotoIM 官方客服',
      isCurrent: false,
      roleTitle: '技术支持与商务咨询',
      totalUnread: 2,
      sessions: owner2Sessions,
    );

    return TrayGroupedUnreadState(totalUnread: 7, groups: [group1, group2]);
  }

  void _syncWithTrayService() {
    try {
      final trayService = ref.read(trayServiceProvider);
      trayService.setUnread(state.totalUnread);
    } catch (_) {}
  }

  /// 标记某个会话为已读
  void markSessionRead(int ownerId, String sessionUnitId) {
    final updatedGroups = <TrayOwnerGroup>[];
    for (final group in state.groups) {
      if (group.ownerId == ownerId) {
        final newSessions =
            group.sessions
                .where((s) => s.sessionUnitId != sessionUnitId)
                .toList();
        final newTotal = newSessions.fold<int>(
          0,
          (sum, s) => sum + s.unreadCount,
        );
        if (newSessions.isNotEmpty) {
          updatedGroups.add(
            group.copyWith(sessions: newSessions, totalUnread: newTotal),
          );
        }
      } else {
        updatedGroups.add(group);
      }
    }

    final newTotal = updatedGroups.fold<int>(
      0,
      (sum, g) => sum + g.totalUnread,
    );
    state = state.copyWith(totalUnread: newTotal, groups: updatedGroups);
    _syncWithTrayService();
  }

  /// 标记特定聊天对象的所有消息为已读
  void markOwnerAllRead(int ownerId) {
    final updatedGroups =
        state.groups.where((g) => g.ownerId != ownerId).toList();
    final newTotal = updatedGroups.fold<int>(
      0,
      (sum, g) => sum + g.totalUnread,
    );
    state = state.copyWith(totalUnread: newTotal, groups: updatedGroups);
    _syncWithTrayService();
  }

  /// 一键全部已读
  void markAllRead() {
    state = TrayGroupedUnreadState.empty;
    _syncWithTrayService();
  }

  /// 模拟收到新消息
  void simulateIncomingMessage({
    required int ownerId,
    required String ownerName,
    required String sessionUnitId,
    required String targetName,
    required String message,
    bool isGroup = false,
  }) {
    final updatedGroups = List<TrayOwnerGroup>.from(state.groups);
    final groupIndex = updatedGroups.indexWhere((g) => g.ownerId == ownerId);

    if (groupIndex >= 0) {
      final existingGroup = updatedGroups[groupIndex];
      final sessionIndex = existingGroup.sessions.indexWhere(
        (s) => s.sessionUnitId == sessionUnitId,
      );
      List<TraySessionItem> updatedSessions;

      if (sessionIndex >= 0) {
        final existingSession = existingGroup.sessions[sessionIndex];
        updatedSessions = List<TraySessionItem>.from(existingGroup.sessions);
        updatedSessions[sessionIndex] = existingSession.copyWith(
          lastMessageText: message,
          unreadCount: existingSession.unreadCount + 1,
          lastMessageTime: DateTime.now(),
        );
      } else {
        updatedSessions = [
          TraySessionItem(
            sessionUnitId: sessionUnitId,
            targetName: targetName,
            lastMessageText: message,
            unreadCount: 1,
            lastMessageTime: DateTime.now(),
            isGroup: isGroup,
          ),
          ...existingGroup.sessions,
        ];
      }

      final newOwnerTotal = updatedSessions.fold<int>(
        0,
        (sum, s) => sum + s.unreadCount,
      );
      updatedGroups[groupIndex] = existingGroup.copyWith(
        sessions: updatedSessions,
        totalUnread: newOwnerTotal,
      );
    } else {
      updatedGroups.add(
        TrayOwnerGroup(
          ownerId: ownerId,
          ownerName: ownerName,
          totalUnread: 1,
          sessions: [
            TraySessionItem(
              sessionUnitId: sessionUnitId,
              targetName: targetName,
              lastMessageText: message,
              unreadCount: 1,
              lastMessageTime: DateTime.now(),
              isGroup: isGroup,
            ),
          ],
        ),
      );
    }

    final newTotal = updatedGroups.fold<int>(
      0,
      (sum, g) => sum + g.totalUnread,
    );
    state = state.copyWith(totalUnread: newTotal, groups: updatedGroups);
    _syncWithTrayService();
  }

  /// 直接重置自定义分组数据
  void setGroups(List<TrayOwnerGroup> groups) {
    final newTotal = groups.fold<int>(0, (sum, g) => sum + g.totalUnread);
    state = TrayGroupedUnreadState(totalUnread: newTotal, groups: groups);
    _syncWithTrayService();
  }
}

/// 托盘未读数据 Provider
final trayGroupedUnreadProvider =
    NotifierProvider<TrayGroupedUnreadNotifier, TrayGroupedUnreadState>(
      TrayGroupedUnreadNotifier.new,
    );
