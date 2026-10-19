import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/window_service.dart';
import '../../../core/widgets/app_badge.dart';
import '../../chat/presentation/chat_page.dart';
import '../application/session_list_controller.dart';
import '../data/models/session_summary.dart';
import 'chat_object_avatar.dart';
import 'desktop_chat_owner_popover.dart';
import 'relative_time_text.dart';
import 'session_last_message_preview.dart';

/// 桌面端微信 4.0 风格分栏会话界面 (DesktopSessionSplitView)
///
/// 核心结构：
/// 1. 左列（290px）：当前身份切换胶囊、搜索栏、置顶折叠栏与会话列表；
/// 2. 右列（自适应）：所选中会话的 [ChatPage] 嵌入渲染，未选会话时展示空状态水印；
/// 3. 双击列表项或点击右侧标题栏图标，可通过 [WindowService] 唤起独立窗口。
class DesktopSessionSplitView extends ConsumerStatefulWidget {
  const DesktopSessionSplitView({required this.controller, super.key});

  final SessionListController controller;

  @override
  ConsumerState<DesktopSessionSplitView> createState() =>
      _DesktopSessionSplitViewState();
}

class _DesktopSessionSplitViewState
    extends ConsumerState<DesktopSessionSplitView> {
  String? _selectedSessionUnitId;
  String? _selectedTitle;
  int? _activeOwnerId;
  bool _isPinnedExpanded = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchKeyword = '';
  double _sessionPaneWidth = 290.0;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() {
      if (mounted) {
        widget.controller.initialize();
      }
    });
  }

  @override
  void didUpdateWidget(DesktopSessionSplitView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller.currentOwner?.id !=
        widget.controller.currentOwner?.id) {
      setState(() {
        _selectedSessionUnitId = null;
        _selectedTitle = null;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _selectSession(SessionSummary session) {
    setState(() {
      _selectedSessionUnitId = session.id;
      _selectedTitle = session.title;
    });
  }

  void _openInStandaloneWindow(SessionSummary session) {
    final ownerId = widget.controller.currentOwner?.id;
    ref
        .read(windowServiceProvider)
        .openChat(
          sessionUnitId: session.id,
          ownerId: ownerId,
          title: session.title,
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;
    final currentOwner = widget.controller.currentOwner;
    final currentOwnerId = currentOwner?.id;

    // 核心身份隔离逻辑：当检测到当前聊天身份改变，立即重置右侧聊天窗口选择状态，坚决杜绝串数据
    if (_activeOwnerId != null && _activeOwnerId != currentOwnerId) {
      _selectedSessionUnitId = null;
      _selectedTitle = null;
    }
    _activeOwnerId = currentOwnerId;

    final allSessions = widget.controller.sessions;
    // 保护：如果当前选中的 session 并不属于当前身份的会话列表，安全重置选择
    if (_selectedSessionUnitId != null &&
        !allSessions.any((s) => s.id == _selectedSessionUnitId)) {
      _selectedSessionUnitId = null;
      _selectedTitle = null;
    }
    final filteredSessions =
        _searchKeyword.isEmpty
            ? allSessions
            : allSessions
                .where(
                  (s) => s.title.toLowerCase().contains(
                    _searchKeyword.toLowerCase(),
                  ),
                )
                .toList();

    final pinnedSessions = filteredSessions
        .where((s) => s.isPinned)
        .toList(growable: false);
    final normalSessions = filteredSessions
        .where((s) => !s.isPinned)
        .toList(growable: false);

    // 经典桌面端颜色规范
    final listPaneBg =
        isDark ? const Color(0xFF232323) : const Color(0xFFF7F7F7);
    final dividerColor =
        isDark ? const Color(0x1FFFFFFF) : const Color(0x1F000000);

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        // P2-03: 当窗口较窄 (例如宽 < 760) 时，动态计算左侧会话栏宽度，保证右侧聊天内容区至少保留 360px，杜绝压缩文字和输入控件
        double effectivePaneWidth = _sessionPaneWidth;
        if (totalWidth.isFinite && totalWidth < 760) {
          final maxPane = (totalWidth - 360.0).clamp(180.0, 260.0);
          if (effectivePaneWidth > maxPane) {
            effectivePaneWidth = maxPane;
          }
        }

        return Row(
          children: [
            // ── 会话列表栏 (左列，宽 effectivePaneWidth) ──────────────────────────
            Container(
              width: effectivePaneWidth,
              color: listPaneBg,
              child: Column(
            children: [
              const SizedBox(height: 12),

              // 1. 顶部：当前身份胶囊 + 快速切换按钮
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Tooltip(
                        message: '点击切换其它聊天身份',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            DesktopChatOwnerPopover.show(
                              context,
                              controller: widget.controller,
                              anchorOffset: const Offset(70, 48),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  isDark
                                      ? Colors.white.withValues(alpha: 0.06)
                                      : Colors.black.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color:
                                    isDark
                                        ? Colors.white.withValues(alpha: 0.08)
                                        : Colors.black.withValues(alpha: 0.06),
                                width: 0.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                AppAvatar(
                                  name: currentOwner?.name ?? '我',
                                  imageUrl: currentOwner?.imageUrl,
                                  radius: 11,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    currentOwner?.name ?? '请选择身份',
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_drop_down_rounded,
                                  size: 18,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // 发起会话 / 快速添加按钮 (+)
                    PopupMenuButton<String>(
                      tooltip: '发起聊天',
                      icon: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color:
                              isDark
                                  ? Colors.white.withValues(alpha: 0.06)
                                  : Colors.black.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.add_rounded,
                          size: 19,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      offset: const Offset(0, 36),
                      onSelected: (val) {
                        if (val == 'create_group') {
                          context.push('/create-group');
                        } else if (val == 'add_friend') {
                          context.push('/add-friend');
                        } else if (val == 'scan') {
                          context.push('/scan-login/scan');
                        }
                      },
                      itemBuilder:
                          (ctx) => [
                            const PopupMenuItem(
                              value: 'create_group',
                              child: Row(
                                children: [
                                  Icon(Icons.group_add_rounded, size: 18),
                                  SizedBox(width: 10),
                                  Text('发起群聊', style: TextStyle(fontSize: 13)),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'add_friend',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.person_add_alt_1_rounded,
                                    size: 18,
                                  ),
                                  SizedBox(width: 10),
                                  Text('添加好友', style: TextStyle(fontSize: 13)),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'scan',
                              child: Row(
                                children: [
                                  Icon(Icons.qr_code_scanner_rounded, size: 18),
                                  SizedBox(width: 10),
                                  Text('扫一扫', style: TextStyle(fontSize: 13)),
                                ],
                              ),
                            ),
                          ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // 2. 搜索框
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Container(
                  height: 32,
                  decoration: BoxDecoration(
                    color:
                        isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(fontSize: 12.5),
                    decoration: InputDecoration(
                      hintText: '搜索',
                      hintStyle: TextStyle(
                        fontSize: 12.5,
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.6,
                        ),
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      prefixIconConstraints: const BoxConstraints(minWidth: 30),
                      suffixIcon:
                          _searchKeyword.isNotEmpty
                              ? IconButton(
                                icon: const Icon(Icons.close_rounded, size: 14),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchKeyword = '');
                                },
                              )
                              : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 7),
                    ),
                    onChanged: (val) => setState(() => _searchKeyword = val),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // 3. 会话列表本体（含折叠置顶）
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [
                    // 微信 4.0 同款：折叠置顶聊天栏
                    if (pinnedSessions.isNotEmpty &&
                        _searchKeyword.isEmpty) ...[
                      InkWell(
                        onTap:
                            () => setState(
                              () => _isPinnedExpanded = !_isPinnedExpanded,
                            ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.format_list_bulleted_rounded,
                                size: 14,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '折叠置顶聊天 (${pinnedSessions.length})',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                _isPinnedExpanded
                                    ? Icons.keyboard_arrow_up_rounded
                                    : Icons.keyboard_arrow_down_rounded,
                                size: 16,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_isPinnedExpanded)
                        for (final session in pinnedSessions)
                          _DesktopSessionItem(
                            session: session,
                            isSelected: session.id == _selectedSessionUnitId,
                            onTap: () => _selectSession(session),
                            onDoubleTap: () => _openInStandaloneWindow(session),
                            onPopOut: () => _openInStandaloneWindow(session),
                          ),
                      Divider(height: 1, thickness: 0.5, color: dividerColor),
                    ],

                    // 常规会话列表
                    for (final session in normalSessions)
                      _DesktopSessionItem(
                        session: session,
                        isSelected: session.id == _selectedSessionUnitId,
                        onTap: () => _selectSession(session),
                        onDoubleTap: () => _openInStandaloneWindow(session),
                        onPopOut: () => _openInStandaloneWindow(session),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── 左右拖拽调节宽度的垂直分割手柄 ──────────────────────────
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (details) {
            setState(() {
              final maxAllowed = (totalWidth.isFinite ? totalWidth - 320.0 : 480.0).clamp(220.0, 480.0);
              _sessionPaneWidth = (_sessionPaneWidth + details.delta.dx).clamp(
                180.0,
                maxAllowed,
              );
            });
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: Container(
              width: 5,
              color: Colors.transparent,
              child: Center(child: Container(width: 0.5, color: dividerColor)),
            ),
          ),
        ),

        // ── 聊天工作区 (右列，自适应) ──────────────────────────────────
        Expanded(
          child:
              _selectedSessionUnitId != null
                  ? ChatPage(
                    key: ValueKey<String>(_selectedSessionUnitId!),
                    ownerId: currentOwner?.id ?? 0,
                    sessionUnitId: _selectedSessionUnitId!,
                    title: _selectedTitle ?? '聊天',
                    isDesktop: true,
                    onPopOut: () {
                      final ownerId = widget.controller.currentOwner?.id;
                      ref
                          .read(windowServiceProvider)
                          .openChat(
                            sessionUnitId: _selectedSessionUnitId!,
                            ownerId: ownerId,
                            title: _selectedTitle,
                          );
                    },
                  )
                  : const _DesktopEmptyChatCanvas(),
        ),
      ],
    );
  },
);
  }
}

class _DesktopSessionItem extends StatelessWidget {
  const _DesktopSessionItem({
    required this.session,
    required this.isSelected,
    required this.onTap,
    required this.onDoubleTap,
    required this.onPopOut,
  });

  final SessionSummary session;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onPopOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    // 微信桌面端选中状态：绿色微高亮
    final activeBg = isDark ? const Color(0x3307C160) : const Color(0x1F07C160);

    return InkWell(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onSecondaryTapDown: (details) {
        // 右键上下文菜单
        showMenu<String>(
          context: context,
          position: RelativeRect.fromLTRB(
            details.globalPosition.dx,
            details.globalPosition.dy,
            details.globalPosition.dx + 1,
            details.globalPosition.dy + 1,
          ),
          items: [
            const PopupMenuItem(
              value: 'popout',
              child: Row(
                children: [
                  Icon(Icons.open_in_new_rounded, size: 16),
                  SizedBox(width: 8),
                  Text('在独立窗口打开', style: TextStyle(fontSize: 12.5)),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'pin',
              child: Row(
                children: [
                  Icon(
                    session.isPinned
                        ? Icons.push_pin_outlined
                        : Icons.push_pin_rounded,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    session.isPinned ? '取消置顶' : '置顶聊天',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'mute',
              child: Row(
                children: [
                  Icon(Icons.notifications_off_outlined, size: 16),
                  SizedBox(width: 8),
                  Text('消息免打扰', style: TextStyle(fontSize: 12.5)),
                ],
              ),
            ),
          ],
        ).then((action) {
          if (action == 'popout') {
            onPopOut();
          }
        });
      },
      child: Container(
        height: 64,
        color: isSelected ? activeBg : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            // 头像与未读状态
            AppBadge(
              count: session.unreadCount,
              dot: session.unreadCount == 0 && session.isMuted,
              size: AppBadgeSize.small,
              child: ChatObjectAvatar(
                name: session.title,
                imageUrl: session.avatarUrl,
                radius: 20,
                chatObjectId: session.destinationId,
              ),
            ),
            const SizedBox(width: 10),

            // 标题、预览与时间
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          session.title,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight:
                                isSelected ? FontWeight.w700 : FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (session.updatedAt != null)
                        RelativeTimeText(
                          time: session.updatedAt!,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: SessionLastMessagePreview(
                          item: session,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.7,
                            ),
                          ),
                        ),
                      ),
                      if (session.isMuted)
                        Icon(
                          Icons.notifications_off_outlined,
                          size: 13,
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.5,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 桌面端微信 4.0 同款未选中会话空状态画布
class _DesktopEmptyChatCanvas extends StatelessWidget {
  const _DesktopEmptyChatCanvas();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;
    final canvasBg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF);

    return Container(
      color: canvasBg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 68,
              color:
                  isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.12),
            ),
            const SizedBox(height: 14),
            Text(
              'Goto IM 桌面端',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '请从左侧列表中选择聊天，或双击打开独立窗口',
              style: TextStyle(
                fontSize: 12.5,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
