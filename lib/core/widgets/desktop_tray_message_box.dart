import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/tray_grouped_unread_provider.dart';
import '../services/tray_message_models.dart';
import '../services/window_service.dart';
import 'app_toast.dart';

/// 桌面端微信同款无边框系统托盘消息聚合浮窗 (DesktopTrayMessageBox)
///
/// 核心契约与设计规范：
/// 1. 微信同款纯净无边框 (border: null)，采用深度暗黑投影与 12dp 现代圆角；
/// 2. 严格按“聊天对象（ChatOwner）”作为一级树状分组：
///    - 一级分组：聊天对象头像 + 身份昵称 + 身份标签 + 【5-新消息总数量】Badge + 折叠展开箭头；
///    - 二级好友/群：好友头像 + 好友昵称/群名 + 消息摘要 + 时间戳 + 单会话未读红点；
/// 3. 点击具体会话：自动切换身份至该聊天对象，并唤醒主窗口聚焦至该会话；
/// 4. 浮窗底部与顶部提供“一键已读”、“打开主界面”及“查看所有会话”快捷操作。
class DesktopTrayMessageBox extends ConsumerStatefulWidget {
  const DesktopTrayMessageBox({super.key});

  /// 在桌面右下角（任务栏托盘上方）弹出微信风格无边框浮窗
  static Future<void> show(BuildContext context) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'DismissTrayFlyout',
      barrierColor: Colors.black.withValues(alpha: 0.25),
      transitionDuration: const Duration(milliseconds: 200),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(curve),
          child: FadeTransition(opacity: curve, child: child),
        );
      },
      pageBuilder: (context, _, _) {
        final media = MediaQuery.of(context);
        return SafeArea(
          child: Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: EdgeInsets.only(
                right: 18,
                bottom: media.size.height > 600 ? 56 : 16,
              ),
              child: const DesktopTrayMessageBox(),
            ),
          ),
        );
      },
    );
  }

  @override
  ConsumerState<DesktopTrayMessageBox> createState() =>
      _DesktopTrayMessageBoxState();
}

class _DesktopTrayMessageBoxState extends ConsumerState<DesktopTrayMessageBox> {
  // 维护各聊天对象的折叠状态 (ownerId -> isCollapsed)
  final Map<int, bool> _collapsedMap = <int, bool>{};
  // 维护各聊天对象内部展开超出初始数量的会话 (ownerId -> showAll)
  final Set<int> _showAllSessionsOwners = <int>{};
  bool _initializedFolding = false;
  final ScrollController _scrollController = ScrollController();

  static const int _maxInitialSessionsPerOwner = 4;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _toggleGroup(int ownerId) {
    setState(() {
      _collapsedMap[ownerId] = !(_collapsedMap[ownerId] ?? false);
    });
  }

  void _toggleShowAllSessions(int ownerId) {
    setState(() {
      if (_showAllSessionsOwners.contains(ownerId)) {
        _showAllSessionsOwners.remove(ownerId);
      } else {
        _showAllSessionsOwners.add(ownerId);
      }
    });
  }

  void _toggleCollapseAll(List<TrayOwnerGroup> groups, bool shouldCollapse) {
    setState(() {
      for (final g in groups) {
        _collapsedMap[g.ownerId] = shouldCollapse;
      }
    });
  }

  void _handleOpenSession(TrayOwnerGroup group, TraySessionItem session) {
    Navigator.of(context).pop();
    final windowService = ref.read(windowServiceProvider);

    showToast(
      '已切换至【${group.ownerName}】并打开【${session.targetName}】',
      type: ToastType.success,
    );

    // 打开或激活该会话对应视窗
    windowService.openChat(
      sessionUnitId: session.sessionUnitId,
      ownerId: group.ownerId,
      title: session.targetName,
    );

    // 标记该会话已读
    ref
        .read(trayGroupedUnreadProvider.notifier)
        .markSessionRead(group.ownerId, session.sessionUnitId);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(trayGroupedUnreadProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 智能默认折叠：当聊天身份大于 1 时，默认仅展开当前活跃身份，其余折叠避免过长霸屏
    if (!_initializedFolding && state.groups.isNotEmpty) {
      _initializedFolding = true;
      if (state.groups.length > 1) {
        for (final g in state.groups) {
          if (!g.isCurrent) {
            _collapsedMap[g.ownerId] = true;
          }
        }
      }
    }

    // 微信 4.0 中性黑灰色阶统一 (#1E1E1E / #232323 / #282828)
    final surfaceBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final cardBg = isDark ? const Color(0xFF232323) : const Color(0xFFF7F7F7);
    final headerBg = isDark ? const Color(0xFF262626) : const Color(0xFFEFEFEF);
    final textMain = isDark ? const Color(0xFFF0F0F0) : const Color(0xFF1F2937);
    final textSecondary =
        isDark ? const Color(0xFF9E9E9E) : const Color(0xFF6B7280);
    const accentGreen = Color(0xFF07C160);
    const accentRed = Color(0xFFFA5151);

    // 动态限制最大高度，防止大/小分辨率屏幕下浮窗顶出桌面或被任务栏遮挡
    final screenH = MediaQuery.of(context).size.height;
    final maxFlyoutHeight = (screenH * 0.72).clamp(380.0, 560.0);

    final allCollapsed =
        state.groups.isNotEmpty &&
        state.groups.every((g) => _collapsedMap[g.ownerId] == true);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 380,
        constraints: BoxConstraints(maxHeight: maxFlyoutHeight),
        decoration: BoxDecoration(
          color: surfaceBg,
          borderRadius: BorderRadius.circular(12),
          // 纯净无边框，完全靠自然层次与高品质柔化阴影形成微信同款界面
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.22),
              blurRadius: 36,
              spreadRadius: 2,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. 浮窗顶部栏 (标题 + 总未读数 + 折叠/展开全部 + 一键已读 + 关闭按钮)
            _buildTopBar(
              headerBg: headerBg,
              textMain: textMain,
              textSecondary: textSecondary,
              accentGreen: accentGreen,
              accentRed: accentRed,
              totalUnread: state.totalUnread,
              groups: state.groups,
              allCollapsed: allCollapsed,
            ),

            // 2. 主体：按聊天对象分组的未读列表（支持原生暗黑细滚动条）
            Flexible(
              child:
                  state.groups.isEmpty
                      ? _buildEmptyState(textSecondary)
                      : RawScrollbar(
                        controller: _scrollController,
                        thumbVisibility: true,
                        thickness: 4.5,
                        radius: const Radius.circular(3),
                        thumbColor:
                            isDark
                                ? Colors.white.withValues(alpha: 0.22)
                                : Colors.black.withValues(alpha: 0.2),
                        child: ListView.separated(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(8),
                          shrinkWrap: true,
                          itemCount: state.groups.length,
                          separatorBuilder:
                              (context, index) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final group = state.groups[index];
                            final isCollapsed =
                                _collapsedMap[group.ownerId] ?? false;
                            final showAllSessions = _showAllSessionsOwners
                                .contains(group.ownerId);

                            return _buildOwnerGroupCard(
                              group: group,
                              isCollapsed: isCollapsed,
                              showAllSessions: showAllSessions,
                              cardBg: cardBg,
                              headerBg: headerBg,
                              textMain: textMain,
                              textSecondary: textSecondary,
                              accentRed: accentRed,
                              accentGreen: accentGreen,
                            );
                          },
                        ),
                      ),
            ),

            // 3. 浮窗底部操作栏 (查看全部会话 + 打开主界面)
            _buildBottomBar(
              headerBg: headerBg,
              textSecondary: textSecondary,
              accentGreen: accentGreen,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar({
    required Color headerBg,
    required Color textMain,
    required Color textSecondary,
    required Color accentGreen,
    required Color accentRed,
    required int totalUnread,
    required List<TrayOwnerGroup> groups,
    required bool allCollapsed,
  }) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: headerBg,
      child: Row(
        children: [
          Text(
            '未读消息提醒',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: textMain,
            ),
          ),
          const SizedBox(width: 8),
          if (totalUnread > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: accentRed,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                totalUnread > 999
                    ? '999+'
                    : (totalUnread > 99 ? '99+' : '$totalUnread'),
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          const Spacer(),
          // 当有多个身份时，提供一键全部折叠/展开，快速收缩视野
          if (groups.length > 1)
            TextButton(
              onPressed: () => _toggleCollapseAll(groups, !allCollapsed),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: textSecondary,
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              child: Text(
                allCollapsed ? '全部展开' : '全部折叠',
                style: const TextStyle(fontSize: 11.5),
              ),
            ),
          if (totalUnread > 0)
            TextButton(
              onPressed: () {
                ref.read(trayGroupedUnreadProvider.notifier).markAllRead();
                showToast('所有新消息已标记为已读', type: ToastType.success);
              },
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: accentGreen,
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              child: const Text('一键已读', style: TextStyle(fontSize: 11.5)),
            ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 16),
            visualDensity: VisualDensity.compact,
            tooltip: '关闭',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildOwnerGroupCard({
    required TrayOwnerGroup group,
    required bool isCollapsed,
    required bool showAllSessions,
    required Color cardBg,
    required Color headerBg,
    required Color textMain,
    required Color textSecondary,
    required Color accentRed,
    required Color accentGreen,
  }) {
    final visibleSessions =
        showAllSessions
            ? group.sessions
            : group.sessions.take(_maxInitialSessionsPerOwner).toList();
    final remainingCount = group.sessions.length - _maxInitialSessionsPerOwner;
    final remainingUnread =
        remainingCount > 0
            ? group.sessions
                .skip(_maxInitialSessionsPerOwner)
                .fold<int>(0, (sum, s) => sum + s.unreadCount)
            : 0;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 一级分组头部：聊天对象头像 + 身份名 + 本组已读 + 5-新消息总数量 + 折叠箭头
          InkWell(
            onTap: () => _toggleGroup(group.ownerId),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              color: headerBg,
              child: Row(
                children: [
                  // 聊天对象头像
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: group.isCurrent ? accentGreen : Colors.blueGrey,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      group.ownerName.isNotEmpty ? group.ownerName[0] : 'IM',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 身份名称与标签
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                group.ownerName,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: textMain,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (group.isCurrent) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: accentGreen.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  '当前身份',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w500,
                                    color: accentGreen,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (group.roleTitle != null)
                          Text(
                            group.roleTitle!,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  // 本组快捷一键已读按钮
                  Tooltip(
                    message: '本身份全部已读',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () {
                        ref
                            .read(trayGroupedUnreadProvider.notifier)
                            .markOwnerAllRead(group.ownerId);
                        showToast(
                          '【${group.ownerName}】的所有消息已标记已读',
                          type: ToastType.success,
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.done_all_rounded,
                          size: 16,
                          color: textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // 5-新消息总数量 Badge (防大数字溢出)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: accentRed.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${group.totalUnread > 99 ? '99+' : group.totalUnread} 条新消息',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFFF6B6B),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    isCollapsed
                        ? Icons.keyboard_arrow_right_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: textSecondary,
                  ),
                ],
              ),
            ),
          ),

          // 二级会话列表（受 _maxInitialSessionsPerOwner 保护，避免霸屏）
          if (!isCollapsed) ...[
            ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: visibleSessions.length,
              itemBuilder: (context, sIndex) {
                final session = visibleSessions[sIndex];
                return _buildSessionItem(
                  group: group,
                  session: session,
                  textMain: textMain,
                  textSecondary: textSecondary,
                  accentRed: accentRed,
                );
              },
            ),
            // 当会话超出阈值时，展示“展开其余 N 个会话”微缩条
            if (remainingCount > 0)
              InkWell(
                onTap: () => _toggleShowAllSessions(group.ownerId),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: headerBg.withValues(alpha: 0.4),
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(8),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        showAllSessions
                            ? '收起部分会话 ▴'
                            : '展开其余 $remainingCount 个会话 (共 $remainingUnread 条新消息) ▾',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: accentGreen,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildSessionItem({
    required TrayOwnerGroup group,
    required TraySessionItem session,
    required Color textMain,
    required Color textSecondary,
    required Color accentRed,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _handleOpenSession(group, session),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            // 好友 / 群 头像
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color:
                    session.isGroup
                        ? const Color(0xFF4A3E72)
                        : const Color(0xFF2E4C6D),
                borderRadius: BorderRadius.circular(5),
              ),
              alignment: Alignment.center,
              child: Text(
                session.targetName.isNotEmpty ? session.targetName[0] : '友',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 名称与消息摘要
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          session.targetName,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: textMain,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (session.lastMessageTime != null)
                        Text(
                          _formatTime(session.lastMessageTime!),
                          style: TextStyle(fontSize: 10, color: textSecondary),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    session.lastMessageText,
                    style: TextStyle(fontSize: 10.5, color: textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            // 单会话未读红点数字
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: accentRed,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                session.unreadCount > 99 ? '99+' : '${session.unreadCount}',
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(Color textSecondary) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.mark_chat_read_outlined,
            size: 40,
            color: textSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 10),
          Text('暂无新未读消息', style: TextStyle(fontSize: 13, color: textSecondary)),
        ],
      ),
    );
  }

  Widget _buildBottomBar({
    required Color headerBg,
    required Color textSecondary,
    required Color accentGreen,
  }) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: headerBg,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          InkWell(
            onTap: () {
              Navigator.of(context).pop();
              ref.read(windowServiceProvider).bringToFront('main');
            },
            child: Text(
              '查看所有会话',
              style: TextStyle(fontSize: 11.5, color: textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              ref.read(windowServiceProvider).bringToFront('main');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: accentGreen,
              foregroundColor: Colors.white,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(5),
              ),
              elevation: 0,
            ),
            child: const Text('打开主界面', style: TextStyle(fontSize: 11.5)),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
