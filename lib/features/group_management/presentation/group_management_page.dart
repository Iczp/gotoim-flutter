import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_toast.dart';
import '../../announcement/presentation/announcement_manage_page.dart';
import '../../chat_settings/application/chat_settings_controller.dart';
import '../../chat_settings/data/models/chat_member.dart';
import '../../chat_settings/presentation/member_list_page.dart';
import '../../chat_settings/presentation/room_join_requests_page.dart';
import '../../session/presentation/chat_object_avatar.dart';
import '../application/group_management_controller.dart';
import '../data/group_management_api.dart';

enum _GroupMgmtSection {
  basic,
  join,
  announcements,
  members,
  orgs,
  admins,
  roles,
  permissions,
  danger,
}

class _MenuItem {
  const _MenuItem({
    required this.section,
    required this.group,
    required this.label,
    required this.icon,
    this.badge = 0,
    this.isDanger = false,
  });

  final _GroupMgmtSection section;
  final String group;
  final String label;
  final IconData icon;
  final int badge;
  final bool isDanger;
}

class GroupManagementPage extends ConsumerStatefulWidget {
  const GroupManagementPage({
    required this.sessionId,
    this.sessionUnitId,
    this.ownerId,
    this.destinationId,
    this.isDialog = false,
    super.key,
  });

  final String sessionId;
  final String? sessionUnitId;
  final int? ownerId;
  final int? destinationId;
  final bool isDialog;

  @override
  ConsumerState<GroupManagementPage> createState() =>
      _GroupManagementPageState();
}

class _GroupManagementPageState extends ConsumerState<GroupManagementPage> {
  late final GroupManagementController controller;
  _GroupMgmtSection _activeSection = _GroupMgmtSection.basic;

  // 基本信息与策略表单
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _isAllMuted = false;
  int _verificationMethod = 0;
  int _invitePolicy = 0;
  int _allowJoinChannels = 7;
  bool _policyFormSeeded = false;

  // 成员列表（供管理员设置与转让群主使用）
  List<ChatMember> _members = const <ChatMember>[];
  bool _loadingMembers = false;
  String? _transferTargetUnitId;
  final _dissolveConfirmCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    controller = GroupManagementController(
      ref.read(groupManagementApiProvider),
      widget.sessionId,
      sessionUnitId: widget.sessionUnitId,
    )..addListener(_onControllerChanged);
    _init();
  }

  Future<void> _init() async {
    await controller.initialize();
    await _loadMembers();
  }

  void _onControllerChanged() {
    final s = controller.settings;
    if (s != null && !_policyFormSeeded) {
      _policyFormSeeded = true;
      _syncFormFromSettings(s);
    }
    final items = _visibleMenuItems();
    if (items.isNotEmpty &&
        !items.any((element) => element.section == _activeSection)) {
      if (mounted) {
        setState(() {
          _activeSection = items.first.section;
        });
      }
    }
  }

  void _syncFormFromSettings(RoomManagementSettings s) {
    _nameCtrl.text = s.name;
    _descCtrl.text = s.description ?? '';
    _isAllMuted = s.isAllMuted;
    _verificationMethod = s.verificationMethod;
    _invitePolicy = s.invitePolicy;
    _allowJoinChannels = s.allowJoinChannels;
  }

  Future<void> _loadMembers() async {
    final unitId = widget.sessionUnitId;
    if (unitId == null || unitId.isEmpty) return;
    final ownerId = widget.ownerId ?? 0;
    if (ownerId <= 0) return;
    if (mounted) setState(() => _loadingMembers = true);
    try {
      final page = await ref
          .read(chatSettingsRepositoryProvider)
          .loadRemoteMembers(ownerId: ownerId, sessionUnitId: unitId, limit: 100);
      if (!mounted) return;
      setState(() {
        _members = page.items;
        _loadingMembers = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMembers = false);
    }
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerChanged);
    controller.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _dissolveConfirmCtrl.dispose();
    super.dispose();
  }

  List<_MenuItem> _visibleMenuItems() {
    final s = controller.settings;
    final items = <_MenuItem>[];

    final canSettings = s?.canManageSettings ?? false;
    final canJoin = s?.canManageJoinRequests ?? false;
    final canAnnouncements = s?.canManageAnnouncements ?? false;
    final canMembers = s?.canManageMembers ?? false;
    final canOrgs = s?.canManageOrgs ?? true;
    final canAdmins = (s?.canManageRoles ?? false) || (s?.isCreator ?? false);
    final canRoles = s?.canManageRoles ?? true;
    final canPermissions = s?.canManagePermissions ?? true;
    final canDanger = s?.canTransferOrDissolve ?? false;

    if (canSettings) {
      items.add(
        const _MenuItem(
          section: _GroupMgmtSection.basic,
          group: '群设置',
          label: '群信息与发言',
          icon: Icons.tune_outlined,
        ),
      );
    }
    if (canJoin || canSettings) {
      items.add(
        _MenuItem(
          section: _GroupMgmtSection.join,
          group: '群设置',
          label: '加群与邀请',
          icon: Icons.person_add_alt_1_outlined,
          badge: s?.pendingJoinRequestCount ?? 0,
        ),
      );
    }
    if (canAnnouncements) {
      items.add(
        _MenuItem(
          section: _GroupMgmtSection.announcements,
          group: '群设置',
          label: '群公告管理',
          icon: Icons.campaign_outlined,
          badge: s?.pendingAnnouncementCount ?? 0,
        ),
      );
    }
    if (canMembers && widget.sessionUnitId != null) {
      items.add(
        const _MenuItem(
          section: _GroupMgmtSection.members,
          group: '成员与架构',
          label: '群成员管理',
          icon: Icons.group_outlined,
        ),
      );
    }
    if (canOrgs) {
      items.add(
        const _MenuItem(
          section: _GroupMgmtSection.orgs,
          group: '成员与架构',
          label: '组织部门',
          icon: Icons.account_tree_outlined,
        ),
      );
    }
    if (canAdmins && widget.sessionUnitId != null) {
      items.add(
        const _MenuItem(
          section: _GroupMgmtSection.admins,
          group: '成员与架构',
          label: '管理员设置',
          icon: Icons.admin_panel_settings_outlined,
        ),
      );
    }
    if (canRoles) {
      items.add(
        const _MenuItem(
          section: _GroupMgmtSection.roles,
          group: '角色与权限',
          label: '群角色管理',
          icon: Icons.badge_outlined,
        ),
      );
    }
    if (canPermissions) {
      items.add(
        const _MenuItem(
          section: _GroupMgmtSection.permissions,
          group: '角色与权限',
          label: '权限矩阵',
          icon: Icons.security_outlined,
        ),
      );
    }
    if (canDanger) {
      items.add(
        const _MenuItem(
          section: _GroupMgmtSection.danger,
          group: '高危操作',
          label: '转让与解散',
          icon: Icons.warning_amber_rounded,
          isDanger: true,
        ),
      );
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final s = controller.settings;
        if (controller.loading) {
          final loader = const Center(child: CircularProgressIndicator());
          return widget.isDialog
              ? loader
              : Scaffold(appBar: AppBar(title: const Text('群管理中心')), body: loader);
        }

        if (s != null && !s.canEnterManagement) {
          final denied = Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.lock_outline_rounded,
                  size: 48,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 12),
                const Text(
                  '需要群管理权限才能进入',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          );
          return widget.isDialog
              ? denied
              : Scaffold(appBar: AppBar(title: const Text('群管理中心')), body: denied);
        }

        final items = _visibleMenuItems();
        final content = LayoutBuilder(
          builder: (context, constraints) {
            final isWide = widget.isDialog || constraints.maxWidth >= 680;
            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _buildLeftSidebar(context, items),
                  const VerticalDivider(width: 1),
                  Expanded(child: _buildWorkspace(context)),
                ],
              );
            }
            return Column(
              children: <Widget>[
                _buildHorizontalNav(context, items),
                const Divider(height: 1),
                Expanded(child: _buildWorkspace(context)),
              ],
            );
          },
        );

        if (widget.isDialog) {
          return content;
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(
              s?.name.isNotEmpty == true ? '${s!.name} · 群管理中心' : '群管理中心',
            ),
          ),
          body: content,
        );
      },
    );
  }

  Widget _buildLeftSidebar(BuildContext context, List<_MenuItem> items) {
    final cs = Theme.of(context).colorScheme;
    final groups = <String>[];
    for (final it in items) {
      if (!groups.contains(it.group)) groups.add(it.group);
    }

    return SizedBox(
      width: 196,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        children: <Widget>[
          for (final g in groups) ...<Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
              child: Text(
                g,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final it in items.where((x) => x.group == g))
              _sidebarTile(context, it),
          ],
        ],
      ),
    );
  }

  Widget _sidebarTile(BuildContext context, _MenuItem item) {
    final cs = Theme.of(context).colorScheme;
    final selected = _activeSection == item.section;
    final fgColor =
        item.isDanger
            ? cs.error
            : (selected ? cs.primary : cs.onSurface);

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color:
            selected
                ? (item.isDanger
                    ? cs.errorContainer.withValues(alpha: 0.45)
                    : cs.primaryContainer.withValues(alpha: 0.55))
                : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _activeSection = item.section),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: <Widget>[
                Icon(item.icon, size: 18, color: fgColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 13,
                      color: fgColor,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (item.badge > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: cs.error,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      item.badge > 99 ? '99+' : '${item.badge}',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onError,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHorizontalNav(BuildContext context, List<_MenuItem> items) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: <Widget>[
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: Icon(item.icon, size: 16),
                label: Text(
                  item.badge > 0 ? '${item.label} (${item.badge})' : item.label,
                ),
                selected: _activeSection == item.section,
                onSelected: (_) => setState(() => _activeSection = item.section),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWorkspace(BuildContext context) {
    return switch (_activeSection) {
      _GroupMgmtSection.basic => _buildBasicSection(context),
      _GroupMgmtSection.join => _buildJoinSection(context),
      _GroupMgmtSection.announcements => _buildAnnouncementsSection(context),
      _GroupMgmtSection.members => _buildMembersSection(context),
      _GroupMgmtSection.orgs => _buildOrgsSection(context),
      _GroupMgmtSection.admins => _buildAdminsSection(context),
      _GroupMgmtSection.roles => _buildRolesSection(context),
      _GroupMgmtSection.permissions => _buildPermissionsSection(context),
      _GroupMgmtSection.danger => _buildDangerSection(context),
    };
  }

  Widget _buildBasicSection(BuildContext context) {
    final s = controller.settings;
    final owners = _members.where((m) => m.isCreator).toList();
    final admins = _members.where((m) => !m.isCreator && m.isAdmin).toList();
    final canViewAdmins =
        (s?.canManageRoles ?? false) || (s?.isCreator ?? false);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text('群信息与发言控制', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 14),
        TextField(
          controller: _nameCtrl,
          maxLength: 64,
          decoration: const InputDecoration(
            labelText: '群聊名称',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _descCtrl,
          maxLines: 3,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: '群简介',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 6),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('全员禁言'),
          subtitle: const Text('开启后仅群主与管理员可在群内发言'),
          value: _isAllMuted,
          onChanged: (v) => setState(() => _isAllMuted = v),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      '当前群主与管理员（${owners.length} 群主 · ${admins.length} 管理员）',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (canViewAdmins && widget.sessionUnitId != null)
                      TextButton(
                        onPressed:
                            () => setState(
                              () => _activeSection = _GroupMgmtSection.admins,
                            ),
                        child: const Text('管理管理员'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final o in owners)
                      Chip(
                        avatar: ChatObjectAvatar(
                          name: o.name,
                          imageUrl: o.avatarUrl.isEmpty ? null : o.avatarUrl,
                          radius: 12,
                          chatObjectId: o.chatObjectId,
                        ),
                        label: Text('${o.name} · 群主'),
                      ),
                    for (final a in admins)
                      Chip(
                        avatar: ChatObjectAvatar(
                          name: a.name,
                          imageUrl: a.avatarUrl.isEmpty ? null : a.avatarUrl,
                          radius: 12,
                          chatObjectId: a.chatObjectId,
                        ),
                        label: Text('${a.name} · 管理员'),
                      ),
                    if (owners.isEmpty && admins.isEmpty)
                      const Text(
                        '暂无识别到的群主或管理员',
                        style: TextStyle(fontSize: 12),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed:
                controller.updating
                    ? null
                    : () async {
                      try {
                        await controller.updateBasicInfo(
                          roomName: _nameCtrl.text,
                          description: _descCtrl.text.trim(),
                          isAllMuted: _isAllMuted,
                        );
                        showToast('群信息与发言设置已保存', type: ToastType.success);
                      } catch (e) {
                        showToast('保存失败：$e', type: ToastType.error);
                      }
                    },
            child: const Text('保存设置'),
          ),
        ),
      ],
    );
  }

  Widget _buildJoinSection(BuildContext context) {
    final s = controller.settings;
    final canSettings = s?.canManageSettings ?? false;
    final canJoin = s?.canManageJoinRequests ?? false;
    final destId = s?.roomId ?? widget.destinationId ?? 0;

    return Column(
      children: <Widget>[
        if (canSettings)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            key: ValueKey('ver-$_verificationMethod'),
                            initialValue: _verificationMethod,
                            decoration: const InputDecoration(
                              labelText: '入群验证方式',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: const <DropdownMenuItem<int>>[
                              DropdownMenuItem(value: 0, child: Text('无需验证')),
                              DropdownMenuItem(value: 1, child: Text('需管理员审核')),
                              DropdownMenuItem(value: 2, child: Text('禁止新成员加入')),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setState(() => _verificationMethod = v);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            key: ValueKey('inv-$_invitePolicy'),
                            initialValue: _invitePolicy,
                            decoration: const InputDecoration(
                              labelText: '邀请策略',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: const <DropdownMenuItem<int>>[
                              DropdownMenuItem(value: 0, child: Text('所有成员可邀请')),
                              DropdownMenuItem(value: 1, child: Text('仅管理员可邀请')),
                              DropdownMenuItem(value: 2, child: Text('邀请需管理员审核')),
                            ],
                            onChanged: (v) {
                              if (v != null) setState(() => _invitePolicy = v);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        const Text('允许入群渠道：', style: TextStyle(fontSize: 12)),
                        FilterChip(
                          label: const Text('成员邀请'),
                          selected: (_allowJoinChannels & 1) != 0,
                          onSelected:
                              (v) => setState(
                                () =>
                                    _allowJoinChannels =
                                        v
                                            ? (_allowJoinChannels | 1)
                                            : (_allowJoinChannels & ~1),
                              ),
                        ),
                        FilterChip(
                          label: const Text('群二维码'),
                          selected: (_allowJoinChannels & 2) != 0,
                          onSelected:
                              (v) => setState(
                                () =>
                                    _allowJoinChannels =
                                        v
                                            ? (_allowJoinChannels | 2)
                                            : (_allowJoinChannels & ~2),
                              ),
                        ),
                        FilterChip(
                          label: const Text('搜索加群'),
                          selected: (_allowJoinChannels & 4) != 0,
                          onSelected:
                              (v) => setState(
                                () =>
                                    _allowJoinChannels =
                                        v
                                            ? (_allowJoinChannels | 4)
                                            : (_allowJoinChannels & ~4),
                              ),
                        ),
                        FilledButton.tonal(
                          onPressed:
                              controller.updating
                                  ? null
                                  : () async {
                                    try {
                                      await controller.updateJoinPolicies(
                                        verificationMethod: _verificationMethod,
                                        invitePolicy: _invitePolicy,
                                        allowJoinChannels: _allowJoinChannels,
                                      );
                                      showToast(
                                        '加群与邀请策略已保存',
                                        type: ToastType.success,
                                      );
                                    } catch (e) {
                                      showToast(
                                        '保存失败：$e',
                                        type: ToastType.error,
                                      );
                                    }
                                  },
                          child: const Text('保存策略'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (canJoin && destId > 0 && widget.sessionUnitId != null)
          Expanded(
            child: RoomJoinRequestsPage(
              destinationId: destId,
              handlerSessionUnitId: widget.sessionUnitId!,
              isDialog: true,
            ),
          ),
      ],
    );
  }

  Widget _buildAnnouncementsSection(BuildContext context) {
    final effectiveSessionId =
        controller.settings?.sessionId.isNotEmpty == true
            ? controller.settings!.sessionId
            : widget.sessionId;
    return AnnouncementManagePage(
      sessionId: effectiveSessionId,
      sessionTitle: controller.settings?.name,
      isEmbedded: true,
      onChanged: controller.refreshSettingsOnly,
    );
  }

  Widget _buildMembersSection(BuildContext context) {
    final unitId = widget.sessionUnitId;
    if (unitId == null || unitId.isEmpty) {
      return const Center(child: Text('缺少当前会话单元信息'));
    }
    final ownerId = widget.ownerId ?? 0;
    return MemberListPage(
      ownerId: ownerId,
      sessionUnitId: unitId,
      isDialog: true,
    );
  }

  Widget _buildOrgsSection(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: <Widget>[
              Text('组织部门', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('新建部门'),
                onPressed: () async {
                  final name = await _nameDialog('新建部门');
                  if (name == null) return;
                  try {
                    await controller.createOrganization(name);
                    showToast('已新建部门', type: ToastType.success);
                  } catch (e) {
                    showToast('操作失败：$e', type: ToastType.error);
                  }
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: _list(
            controller.organizations,
            empty: '暂无部门',
            item:
                (item) => ListTile(
                  leading: const Icon(Icons.account_tree_outlined),
                  title: Text(item.name),
                  subtitle: Text('ID: ${item.id}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      IconButton(
                        icon: const Icon(Icons.add),
                        tooltip: '添加子部门',
                        onPressed: () async {
                          final name = await _nameDialog('新建子部门');
                          if (name != null) {
                            try {
                              await controller.createOrganization(
                                name,
                                parentId: item.id,
                              );
                            } catch (e) {
                              showToast('操作失败：$e', type: ToastType.error);
                            }
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: '删除部门',
                        onPressed: () async {
                          try {
                            await controller.deleteOrganization(item.id);
                          } catch (e) {
                            showToast('删除失败：$e', type: ToastType.error);
                          }
                        },
                      ),
                    ],
                  ),
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildAdminsSection(BuildContext context) {
    final isCreator = controller.settings?.isCreator ?? false;
    final owners = _members.where((m) => m.isCreator).toList();
    final admins = _members.where((m) => !m.isCreator && m.isAdmin).toList();
    final candidates =
        _members.where((m) => !m.isCreator && !m.isAdmin).toList();

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: <Widget>[
              Text('群管理员设置', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              if (isCreator)
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.person_add_outlined, size: 16),
                  label: const Text('添加管理员'),
                  onPressed:
                      candidates.isEmpty
                          ? null
                          : () => _pickAndPromoteAdmin(candidates),
                ),
            ],
          ),
        ),
        Expanded(
          child:
              _loadingMembers
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: <Widget>[
                      for (final o in owners)
                        ListTile(
                          leading: ChatObjectAvatar(
                            name: o.name,
                            imageUrl: o.avatarUrl.isEmpty ? null : o.avatarUrl,
                            radius: 18,
                            chatObjectId: o.chatObjectId,
                          ),
                          title: Text(o.name),
                          trailing: const Chip(
                            label: Text(
                              '群主',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.amber,
                              ),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      if (admins.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: Text('暂未设置群管理员')),
                        )
                      else
                        for (final a in admins)
                          ListTile(
                            leading: ChatObjectAvatar(
                              name: a.name,
                              imageUrl:
                                  a.avatarUrl.isEmpty ? null : a.avatarUrl,
                              radius: 18,
                              chatObjectId: a.chatObjectId,
                            ),
                            title: Text(a.name),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                const Chip(
                                  label: Text(
                                    '管理员',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.blue,
                                    ),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                                if (isCreator) ...<Widget>[
                                  const SizedBox(width: 6),
                                  TextButton(
                                    onPressed: () => _setAdmin(a, false),
                                    child: const Text('取消管理员'),
                                  ),
                                ],
                              ],
                            ),
                          ),
                    ],
                  ),
        ),
      ],
    );
  }

  Future<void> _pickAndPromoteAdmin(List<ChatMember> candidates) async {
    final selected = await showDialog<ChatMember>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('选择群成员设为管理员'),
            content: SizedBox(
              width: 360,
              height: 360,
              child: ListView.builder(
                itemCount: candidates.length,
                itemBuilder: (ctx, i) {
                  final m = candidates[i];
                  return ListTile(
                    title: Text(m.name),
                    onTap: () => Navigator.pop(ctx, m),
                  );
                },
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
            ],
          ),
    );
    if (selected != null) {
      await _setAdmin(selected, true);
    }
  }

  Future<void> _setAdmin(ChatMember member, bool isAdmin) async {
    try {
      await ref.read(groupManagementApiProvider).setAdmin(member.id, isAdmin);
      showToast(
        isAdmin ? '已将 ${member.name} 设为管理员' : '已取消 ${member.name} 的管理员',
        type: ToastType.success,
      );
      await _loadMembers();
    } catch (e) {
      showToast('操作失败：$e', type: ToastType.error);
    }
  }

  Widget _buildRolesSection(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: <Widget>[
              Text('群角色管理', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('新建角色'),
                onPressed: () async {
                  final name = await _nameDialog('新建角色');
                  if (name == null) return;
                  try {
                    await controller.createRole(name);
                    showToast('已创建角色', type: ToastType.success);
                  } catch (e) {
                    showToast('创建失败：$e', type: ToastType.error);
                  }
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: _list(
            controller.roles,
            empty: '暂无角色',
            item: (item) {
              final selected = controller.selectedRoleId == item.id;
              return ListTile(
                leading: Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color:
                      selected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outline,
                ),
                title: Text(item.name),
                subtitle: Text('ID: ${item.id}'),
                onTap:
                    controller.updating
                        ? null
                        : () => controller.selectRole(item.id),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    try {
                      await controller.deleteRole(item.id);
                    } catch (e) {
                      showToast('删除失败：$e', type: ToastType.error);
                    }
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionsSection(BuildContext context) {
    if (controller.roles.isEmpty) {
      return const Center(child: Text('请先在「群角色管理」中创建角色'));
    }
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('role-${controller.selectedRoleId}'),
                  initialValue: controller.selectedRoleId,
                  decoration: const InputDecoration(
                    labelText: '选择群角色',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items:
                      controller.roles
                          .map(
                            (r) => DropdownMenuItem<String>(
                              value: r.id,
                              child: Text(r.name),
                            ),
                          )
                          .toList(),
                  onChanged: (v) {
                    if (v != null) controller.selectRole(v);
                  },
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed:
                    controller.updating
                        ? null
                        : () => controller.setAllPermissions(true),
                child: const Text('全开'),
              ),
              const SizedBox(width: 4),
              OutlinedButton(
                onPressed:
                    controller.updating
                        ? null
                        : () => controller.setAllPermissions(false),
                child: const Text('全关'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _list(
            controller.permissions,
            empty: '暂无权限定义',
            item:
                (item) => CheckboxListTile(
                  value: controller.grantedPermissionIds.contains(item.id),
                  onChanged:
                      controller.updating
                          ? null
                          : (value) =>
                              controller.togglePermission(item, value ?? false),
                  title: Text(item.name),
                  subtitle: Text('ID: ${item.id}'),
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildDangerSection(BuildContext context) {
    final s = controller.settings;
    final candidates =
        _members
            .where((m) => !m.isCreator && m.id != widget.sessionUnitId)
            .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(
          '高危操作',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Theme.of(context).colorScheme.error,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text(
                  '转让群主',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: ValueKey('transfer-$_transferTargetUnitId'),
                  initialValue: _transferTargetUnitId,
                  hint: const Text('选择新群主成员'),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items:
                      candidates
                          .map(
                            (m) => DropdownMenuItem<String>(
                              value: m.id,
                              child: Text(m.name),
                            ),
                          )
                          .toList(),
                  onChanged: (v) => setState(() => _transferTargetUnitId = v),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton(
                    onPressed:
                        (_transferTargetUnitId == null || controller.updating)
                            ? null
                            : () async {
                              try {
                                await controller.transferCreator(
                                  _transferTargetUnitId!,
                                );
                                showToast('群主已转让', type: ToastType.success);
                                if (!context.mounted) return;
                                Navigator.of(context).pop(true);
                              } catch (e) {
                                showToast('转让失败：$e', type: ToastType.error);
                              }
                            },
                    child: const Text('确认转让群主'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.25),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: Theme.of(context).colorScheme.error),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  '解散群聊',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  s?.name.isNotEmpty == true
                      ? '输入群名称「${s!.name}」确认解散群聊，解散后不可恢复。'
                      : '解散后所有成员将被移除且不可恢复。',
                  style: const TextStyle(fontSize: 12),
                ),
                if (s?.name.isNotEmpty == true) ...<Widget>[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _dissolveConfirmCtrl,
                    decoration: InputDecoration(
                      hintText: '输入「${s!.name}」',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                    onPressed:
                        controller.updating
                            ? null
                            : () async {
                              final expected = s?.name.trim() ?? '';
                              if (expected.isNotEmpty &&
                                  _dissolveConfirmCtrl.text.trim() != expected) {
                                showToast(
                                  '请输入群名称「$expected」以确认',
                                  type: ToastType.warning,
                                );
                                return;
                              }
                              try {
                                await controller.dissolveRoom();
                                showToast('群聊已解散', type: ToastType.success);
                                if (!context.mounted) return;
                                Navigator.of(context).pop(true);
                              } catch (e) {
                                showToast('解散失败：$e', type: ToastType.error);
                              }
                            },
                    child: const Text('确认解散群聊'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _list(
    List<IdNameItem> items, {
    required String empty,
    required Widget Function(IdNameItem item) item,
  }) => RefreshIndicator(
    onRefresh: controller.initialize,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: <Widget>[
        if (controller.error != null)
          MaterialBanner(
            content: Text('操作失败：${controller.error}'),
            actions: <Widget>[
              TextButton(
                onPressed: controller.initialize,
                child: const Text('重试'),
              ),
            ],
          ),
        if (items.isEmpty)
          SizedBox(height: 240, child: Center(child: Text(empty)))
        else
          ...items.map(item),
      ],
    ),
  );

  Future<String?> _nameDialog(String title) async {
    final input = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(title),
            content: TextField(
              controller: input,
              autofocus: true,
              decoration: const InputDecoration(hintText: '名称'),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, input.text.trim()),
                child: const Text('保存'),
              ),
            ],
          ),
    );
    input.dispose();
    return result?.isEmpty == true ? null : result;
  }
}
