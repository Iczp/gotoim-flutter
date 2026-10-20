import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell/application_shell.dart';
import '../../home/presentation/home_sections.dart';
import '../../session/application/session_list_controller.dart';
import '../../session/presentation/chat_object_avatar.dart';
import '../../session/presentation/desktop_session_split_view.dart';
import '../../user/data/models/profile_subject.dart';
import '../../user/presentation/widgets/profile_action_sheets.dart';
import '../../user/presentation/widgets/profile_gender_badge.dart';
import '../application/contacts_controller.dart';
import '../data/models/contact_group.dart';
import 'widgets/contact_row.dart';

/// 桌面端微信 4.0 风格通讯录三栏主视图 (DesktopContactsSplitView)
///
/// 核心结构：
/// 1. 左栏（导航 Dock）：由应用外层 ApplicationShell 统一承载；
/// 2. 中栏（290px，可拖拽调节宽度）：搜索栏、快捷入口（新的朋友/群聊/标签）、A-Z字母分组联系人列表；
/// 3. 右栏（自适应）：在第三栏直接展示所选中联系人的完整详细资料卡与发消息操作，未选时展示空状态水印。
class DesktopContactsSplitView extends ConsumerStatefulWidget {
  const DesktopContactsSplitView({super.key});

  @override
  ConsumerState<DesktopContactsSplitView> createState() =>
      _DesktopContactsSplitViewState();
}

class _DesktopContactsSplitViewState
    extends ConsumerState<DesktopContactsSplitView> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  ContactEntry? _selectedContact;
  String? _selectedQuickAction;
  String _searchKeyword = '';
  double _contactsPaneWidth = 290.0;
  int? _activeOwnerId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(sessionListControllerProvider).initialize();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _openChat(ContactEntry contact) {
    // 1. 切换全局主 Tab 至消息页
    ref
        .read(currentHomeSectionProvider.notifier)
        .setSection(HomeSection.messages);
    // 2. 联动激活右侧对应的聊天会话
    ref
        .read(selectedDesktopSessionUnitIdProvider.notifier)
        .select(contact.id);
  }

  Future<void> _showContactContextMenu(
    BuildContext context,
    TapDownDetails details,
    ContactEntry contact,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final position = RelativeRect.fromRect(
      details.globalPosition & const Size(1, 1),
      Offset.zero & overlay.size,
    );

    final action = await showMenu<String>(
      context: context,
      position: position,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: const [
        PopupMenuItem<String>(
          value: 'chat',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.chat_bubble_outline_rounded, size: 16),
              SizedBox(width: 8),
              Text('发消息', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'profile',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.badge_outlined, size: 16),
              SizedBox(width: 8),
              Text('查看资料', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ],
    );

    if (action == null || !mounted) return;

    if (action == 'chat') {
      _openChat(contact);
    } else if (action == 'profile') {
      setState(() {
        _selectedContact = contact;
        _selectedQuickAction = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;
    final sessions = ref.watch(sessionListControllerProvider);
    final contacts = ref.watch(contactsControllerProvider);
    final ownerId = sessions.currentOwner?.id;

    if (ownerId != null && contacts.ownerId != ownerId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(contactsControllerProvider).initialize(ownerId);
      });
    }

    if (_activeOwnerId != null && _activeOwnerId != ownerId) {
      _selectedContact = null;
      _selectedQuickAction = null;
    }
    _activeOwnerId = ownerId;

    final groups = contacts.groups;
    final isInitialLoading =
        groups.isEmpty && (contacts.isLoading || contacts.ownerId != ownerId);

    // 搜索过滤
    final filteredGroups = <ContactGroup>[];
    if (_searchKeyword.isEmpty) {
      filteredGroups.addAll(groups);
    } else {
      for (final group in groups) {
        final matches =
            group.contacts
                .where(
                  (c) => c.displayName.toLowerCase().contains(
                    _searchKeyword.toLowerCase(),
                  ),
                )
                .toList();
        if (matches.isNotEmpty) {
          filteredGroups.add(ContactGroup(index: group.index, contacts: matches));
        }
      }
    }

    final listPaneBg =
        isDark ? const Color(0xFF232323) : const Color(0xFFF7F7F7);
    final dividerColor =
        isDark ? const Color(0x1FFFFFFF) : const Color(0x1F000000);

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        double effectivePaneWidth = _contactsPaneWidth;
        if (totalWidth.isFinite && totalWidth < 760) {
          final maxPane = (totalWidth - 360.0).clamp(180.0, 260.0);
          if (effectivePaneWidth > maxPane) {
            effectivePaneWidth = maxPane;
          }
        }

        return Row(
          children: [
            // ── 通讯录列表栏 (中栏，宽 effectivePaneWidth) ──────────────────────────
            Container(
              width: effectivePaneWidth,
              color: listPaneBg,
              child: Column(
                children: [
                  const SizedBox(height: 12),

                  // 1. 搜索框
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
                          hintText: '搜索联系人',
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
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 30,
                          ),
                          suffixIcon:
                              _searchKeyword.isNotEmpty
                                  ? IconButton(
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 14,
                                    ),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchKeyword = '');
                                    },
                                  )
                                  : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 7,
                          ),
                        ),
                        onChanged:
                            (val) => setState(() => _searchKeyword = val),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // 2. 快捷功能入口与联系人列表
                  Expanded(
                    child:
                        isInitialLoading
                            ? const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                            : ListView(
                              controller: _scrollController,
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              children: [
                                // 快捷功能：仅在非搜索模式展示
                                if (_searchKeyword.isEmpty) ...[
                                  _QuickActionRow(
                                    icon: Icons.person_add_alt_1_rounded,
                                    iconBgColor: const Color(0xFFFA9D3B),
                                    title: '新的朋友',
                                    isSelected:
                                        _selectedQuickAction == 'new_friends',
                                    onTap: () {
                                      setState(() {
                                        _selectedQuickAction = 'new_friends';
                                        _selectedContact = null;
                                      });
                                    },
                                  ),
                                  _QuickActionRow(
                                    icon: Icons.group_rounded,
                                    iconBgColor: const Color(0xFF07C160),
                                    title: '群聊',
                                    isSelected: _selectedQuickAction == 'groups',
                                    onTap: () {
                                      setState(() {
                                        _selectedQuickAction = 'groups';
                                        _selectedContact = null;
                                      });
                                    },
                                  ),
                                  _QuickActionRow(
                                    icon: Icons.label_rounded,
                                    iconBgColor: const Color(0xFF2782D7),
                                    title: '标签',
                                    isSelected: _selectedQuickAction == 'tags',
                                    onTap: () {
                                      setState(() {
                                        _selectedQuickAction = 'tags';
                                        _selectedContact = null;
                                      });
                                    },
                                  ),
                                  Divider(
                                    height: 1,
                                    thickness: 0.5,
                                    color: dividerColor,
                                  ),
                                ],

                                // 分组联系人列表
                                if (filteredGroups.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Center(
                                      child: Text(
                                        _searchKeyword.isNotEmpty
                                            ? '未找到匹配联系人'
                                            : '暂无联系人',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: colorScheme.onSurfaceVariant
                                              .withValues(alpha: 0.6),
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  for (final group in filteredGroups) ...[
                                    _DesktopGroupHeader(title: group.index),
                                    for (
                                      var i = 0;
                                      i < group.contacts.length;
                                      i++
                                    ) ...[
                                      ContactRow(
                                        contact: group.contacts[i],
                                        isSelected:
                                            _selectedContact?.id ==
                                            group.contacts[i].id,
                                        showDivider:
                                            i + 1 < group.contacts.length,
                                        onTap: () {
                                          setState(() {
                                            _selectedContact =
                                                group.contacts[i];
                                            _selectedQuickAction = null;
                                          });
                                        },
                                        onDoubleTap:
                                            () =>
                                                _openChat(group.contacts[i]),
                                        onSecondaryTapDown:
                                            (details) =>
                                                _showContactContextMenu(
                                                  context,
                                                  details,
                                                  group.contacts[i],
                                                ),
                                      ),
                                    ],
                                  ],

                                if (filteredGroups.isNotEmpty &&
                                    _searchKeyword.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 20,
                                    ),
                                    child: Center(
                                      child: Text(
                                        '共有 ${contacts.totalCount} 位联系人',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: colorScheme.onSurfaceVariant
                                              .withValues(alpha: 0.6),
                                        ),
                                      ),
                                    ),
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
                  final maxAllowed = (totalWidth.isFinite
                          ? totalWidth - 320.0
                          : 480.0)
                      .clamp(220.0, 480.0);
                  _contactsPaneWidth = (_contactsPaneWidth + details.delta.dx)
                      .clamp(180.0, maxAllowed);
                });
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: Container(
                  width: 5,
                  color: Colors.transparent,
                  child: Center(
                    child: Container(width: 0.5, color: dividerColor),
                  ),
                ),
              ),
            ),

            // ── 第三栏：具体个人详细资料卡 / 快捷功能界面 (右列，自适应) ─────────────────
            Expanded(
              child:
                  _selectedContact != null
                      ? DesktopContactDetailView(
                        contact: _selectedContact!,
                        onSendMessage: () => _openChat(_selectedContact!),
                      )
                      : _selectedQuickAction != null
                      ? _DesktopQuickActionCanvas(action: _selectedQuickAction!)
                      : const _DesktopEmptyContactCanvas(),
            ),
          ],
        );
      },
    );
  }
}

/// 桌面端联系人 A-Z 分组标题小条
class _DesktopGroupHeader extends StatelessWidget {
  const _DesktopGroupHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      height: 26,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color:
          isDark
              ? Colors.white.withValues(alpha: 0.03)
              : Colors.black.withValues(alpha: 0.025),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

/// 快捷入口行（新的朋友、群聊、标签）
class _QuickActionRow extends StatelessWidget {
  const _QuickActionRow({
    required this.icon,
    required this.iconBgColor,
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final Color iconBgColor;
  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final activeBg = isDark ? const Color(0x3307C160) : const Color(0x1F07C160);

    return Material(
      color: isSelected ? activeBg : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 桌面端微信 4.0 风格联系人详细资料视图（第三栏打开）
class DesktopContactDetailView extends StatelessWidget {
  const DesktopContactDetailView({
    required this.contact,
    required this.onSendMessage,
    super.key,
  });

  final ContactEntry contact;
  final VoidCallback onSendMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;
    final data = ProfileData(ProfileSubject.contact(contact));
    final canvasBg =
        isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF);
    final cardBg =
        isDark ? const Color(0xFF282828) : const Color(0xFFF9F9F9);
    final dividerColor =
        isDark ? const Color(0x1FFFFFFF) : const Color(0x1F000000);

    return Container(
      color: canvasBg,
      child: Column(
        children: [
          // 顶栏操作区
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: dividerColor, width: 0.5)),
            ),
            child: Row(
              children: [
                Text(
                  '详细资料',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.more_horiz_rounded, size: 20),
                  tooltip: '更多选项',
                  onPressed: () {
                    showMoreProfileActionSheet(
                      context,
                      userId: contact.id,
                      userName: data.displayName,
                    );
                  },
                ),
              ],
            ),
          ),

          // 核心个人资料主体区（自适应居中卡片）
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 48,
                  vertical: 36,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. 头像与姓名区域
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ChatObjectAvatar(
                            name: data.displayName,
                            imageUrl:
                                contact.avatarUrl.isEmpty
                                    ? null
                                    : contact.avatarUrl,
                            radius: 34,
                            chatObjectId: data.chatObjectId,
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        data.displayName,
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w700,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (data.gender != 0) ...[
                                      const SizedBox(width: 8),
                                      ProfileGenderBadge(gender: data.gender),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 6),
                                if (data.showNickname) ...[
                                  Text(
                                    '昵称: ${data.originalNickname}',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: colorScheme.onSurfaceVariant
                                          .withValues(alpha: 0.7),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                ],
                                Text(
                                  '微信号: ${data.accountCode.isEmpty ? '-' : data.accountCode}',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),
                      Divider(height: 1, thickness: 0.5, color: dividerColor),
                      const SizedBox(height: 18),

                      // 2. 详细信息行组
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: dividerColor, width: 0.5),
                        ),
                        child: Column(
                          children: [
                            _InfoRow(
                              label: '地区',
                              value:
                                  data.region.isNotEmpty ? data.region : '未知',
                            ),
                            if (data.description.isNotEmpty) ...[
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                child: Divider(
                                  height: 0.5,
                                  thickness: 0.5,
                                  color: dividerColor,
                                ),
                              ),
                              _InfoRow(
                                label: '个性签名',
                                value: data.description,
                              ),
                            ],
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Divider(
                                height: 0.5,
                                thickness: 0.5,
                                color: dividerColor,
                              ),
                            ),
                            const _InfoRow(
                              label: '来源',
                              value: '通过通讯录添加',
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 36),

                      // 3. 底部发消息大按钮（微信经典绿色主按钮）
                      FilledButton.icon(
                        onPressed: onSendMessage,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF07C160),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                        icon: const Icon(
                          Icons.chat_bubble_rounded,
                          size: 19,
                        ),
                        label: const Text(
                          '发消息',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () {
                          showMediaCallActionSheet(context, data.displayName);
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          side: BorderSide(color: dividerColor, width: 0.8),
                        ),
                        icon: Icon(
                          Icons.videocam_outlined,
                          size: 20,
                          color: colorScheme.onSurface,
                        ),
                        label: Text(
                          '音视频通话',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

/// 桌面端快捷功能右侧画布（新的朋友、群聊、标签）
class _DesktopQuickActionCanvas extends StatelessWidget {
  const _DesktopQuickActionCanvas({required this.action});

  final String action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;
    final canvasBg =
        isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF);

    final title = switch (action) {
      'new_friends' => '新的朋友',
      'groups' => '群聊列表',
      'tags' => '标签管理',
      _ => '功能中心',
    };

    final icon = switch (action) {
      'new_friends' => Icons.person_add_alt_1_rounded,
      'groups' => Icons.group_rounded,
      'tags' => Icons.label_rounded,
      _ => Icons.widgets_rounded,
    };

    return Container(
      color: canvasBg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 64,
              color: colorScheme.primary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '可点击上方操作添加或管理对应项目',
              style: TextStyle(
                fontSize: 12.5,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 桌面端未选中联系人空状态水印画布
class _DesktopEmptyContactCanvas extends StatelessWidget {
  const _DesktopEmptyContactCanvas();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;
    final canvasBg =
        isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF);

    return Container(
      color: canvasBg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.contacts_outlined,
              size: 68,
              color:
                  isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.12),
            ),
            const SizedBox(height: 14),
            Text(
              'Goto IM 通讯录',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '请从左侧列表中选择联系人查看详细资料',
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
