import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_modal.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/cell_group.dart';
import '../../../core/widgets/desktop_dialog.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/config/app_environment.dart';
import '../../../core/media/image_provider_factory.dart';
import '../../../core/utils/api_url_resolver.dart';
import '../../session/application/session_list_controller.dart';
import '../../session/data/models/session_summary.dart';
import '../../session/presentation/chat_object_avatar.dart';
import '../../settings/presentation/message_alert_settings_page.dart';
import '../../user/presentation/profile_page.dart';
import '../../mine/presentation/my_qr_code_dialog.dart';
import '../../mine/presentation/my_qr_code_page.dart';
import '../../group/data/room_api.dart';
import '../../group_management/application/group_management_controller.dart';
import '../../group_management/data/group_management_api.dart';
import '../../group_management/presentation/group_management_page.dart';
import '../../announcement/presentation/announcement_list_page.dart';
import '../application/chat_settings_controller.dart';
import '../data/models/chat_member.dart';
import 'chat_background_page.dart';
import 'chat_background_preview_page.dart';
import 'member_list_page.dart';
import 'member_tile.dart';
import '../../../core/security/widgets/report_dialog.dart';

enum ChatSettingsResult { messagesCleared, sessionLeft }

class ChatSettingsPage extends ConsumerStatefulWidget {
  const ChatSettingsPage({
    required this.ownerId,
    required this.sessionUnitId,
    this.isDrawer = false,
    this.onClose,
    this.onMessagesCleared,
    this.onSessionLeft,
    super.key,
  });
  final int ownerId;
  final String sessionUnitId;
  final bool isDrawer;
  final VoidCallback? onClose;
  final VoidCallback? onMessagesCleared;
  final VoidCallback? onSessionLeft;

  @override
  ConsumerState<ChatSettingsPage> createState() => _ChatSettingsPageState();
}

class _ChatSettingsPageState extends ConsumerState<ChatSettingsPage> {
  late final ChatSettingsController controller;
  RoomManagementSettings? _roomMgmtSettings;

  @override
  void initState() {
    super.initState();
    controller = ChatSettingsController(
      ref.read(chatSettingsRepositoryProvider),
      ref.read(sessionRepositoryProvider),
      ownerId: widget.ownerId,
      sessionUnitId: widget.sessionUnitId,
      roomApi: ref.read(roomApiProvider),
    )..addListener(_onControllerUpdated);
    controller.initialize();
  }

  void _onControllerUpdated() {
    if (controller.isGroup && _roomMgmtSettings == null) {
      _loadRoomMgmtSettings();
    }
  }

  Future<void> _loadRoomMgmtSettings() async {
    try {
      final res = await ref
          .read(groupManagementApiProvider)
          .getManagementSettings(widget.sessionUnitId);
      if (mounted) {
        setState(() => _roomMgmtSettings = res);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerUpdated);
    controller.dispose();
    super.dispose();
  }

  void _openGroupQrCode() {
    final friend = controller.friend;
    if (friend == null) return;
    final groupOwnerId = friend.destinationId;
    if (groupOwnerId == null || groupOwnerId <= 0) return;

    final isDesktop = MediaQuery.sizeOf(context).width >= 720;
    if (isDesktop) {
      MyQrCodeDialog.show(
        context,
        isGroup: true,
        groupOwnerId: groupOwnerId,
        groupTitle: controller.title,
        groupAvatar: _avatarFor(friend),
        inviterId: widget.ownerId,
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MyQrCodePage(
          isGroup: true,
          groupOwnerId: groupOwnerId,
          groupTitle: controller.title,
          groupAvatar: _avatarFor(friend),
          inviterId: widget.ownerId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final horizontalPadding =
        MediaQuery.sizeOf(context).width > 700 ? 32.0 : 16.0;

    return AnimatedBuilder(
      animation: controller,
      builder:
          (context, _) => Scaffold(
            appBar: AppBar(
              title: const Text('聊天设置'),
              leading:
                  widget.isDrawer
                      ? IconButton(
                        icon: const Icon(Icons.close_rounded),
                        tooltip: '关闭',
                        onPressed:
                            widget.onClose ?? () => Navigator.of(context).pop(),
                      )
                      : null,
            ),
            body: RefreshIndicator(
              onRefresh: controller.refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  16,
                  horizontalPadding,
                  24,
                ),
                children: <Widget>[
                  if (controller.error != null)
                    MaterialBanner(
                      content: Text('加载失败：${controller.error}'),
                      actions: <Widget>[
                        TextButton(
                          onPressed: controller.refresh,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  _MemberPreview(controller: controller),
                  if (controller.friend != null)
                    _section(<Widget>[
                      Cell(
                        icon: ChatObjectAvatar(
                          name: controller.friend!.title,
                          imageUrl: _avatarFor(controller.friend!),
                          radius: 20,
                          chatObjectId: controller.friend!.destinationId,
                        ),
                        title: controller.objectType == 2 ? '查看群资料' : '查看好友资料',
                        subtitle: controller.friend!.title,
                        showArrow: true,
                        onTap:
                            () => openProfilePage(
                              context,
                              subject: ProfileSubject.session(
                                controller.friend!,
                              ),
                            ),
                      ),
                    ], title: '会话信息'),
                  _section(<Widget>[
                    Cell(title: '类型', value: controller.objectTypeLabel),
                    if (controller.objectType == 2)
                      Cell(
                        title: '群名称',
                        value: controller.title,
                        showArrow: true,
                        onTap: _editGroupName,
                      ),
                    if (controller.objectType == 2 && controller.friend != null)
                      Cell(
                        title: '群二维码',
                        trailing: const Icon(Icons.qr_code_2_rounded, size: 20),
                        showArrow: true,
                        onTap: _openGroupQrCode,
                      ),
                    Cell(
                      title: controller.objectType == 2 ? '我在本群的昵称' : '设置备注',
                      value:
                          controller.rename.isNotEmpty
                              ? controller.rename
                              : '未设置',
                      showArrow: true,
                      onTap: _editRename,
                    ),
                  ], title: '聊天设置'),
                  _section(<Widget>[
                    Cell(
                      icon: const Icon(Icons.search_rounded),
                      title: '查找聊天记录',
                      showArrow: true,
                      onTap:
                          () => showToast('查找聊天记录功能即将上线', type: ToastType.info),
                    ),
                    Builder(
                      builder: (context) {
                        final rawBg = controller.backgroundImage;
                        final hasBg = rawBg != null && rawBg.isNotEmpty;
                        final bgUrl = hasBg
                            ? resolveApiUrl(
                                rawBg,
                                ref.watch(appEnvironmentProvider).apiBaseUrl,
                              )
                            : null;
                        return Cell(
                          icon: const Icon(Icons.wallpaper_rounded),
                          title: '设置聊天背景',
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              if (hasBg && bgUrl != null) ...[
                                GestureDetector(
                                  onTap: () => _previewCurrentBackground(bgUrl),
                                  child: Container(
                                    width: 32,
                                    height: 32,
                                    margin: const EdgeInsets.only(right: 4),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outlineVariant
                                            .withValues(alpha: 0.6),
                                        width: 1,
                                      ),
                                      image: DecorationImage(
                                        image: createImageProvider(bgUrl),
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: '删除背景',
                                  onPressed: _confirmClearBackground,
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 20,
                                  ),
                                ),
                              ] else
                                Text(
                                  '默认',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant
                                        .withValues(alpha: 0.6),
                                  ),
                                ),
                              const SizedBox(width: 2),
                              Icon(
                                Icons.chevron_right,
                                size: 18,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: 0.5),
                              ),
                            ],
                          ),
                          onTap: _openBackgroundSettings,
                        );
                      },
                    ),
                  ], title: '功能'),
                  _section(<Widget>[
                    Cell(
                      icon: const Icon(Icons.notifications_active_outlined),
                      title: '消息提醒',
                      subtitle: '本会话的通知、声音、振动与消息预览',
                      showArrow: true,
                      onTap: () {
                        if (widget.isDrawer) {
                          showDesktopModalDialog<void>(
                            context: context,
                            title: '消息提醒设置',
                            subtitle: controller.title,
                            width: 480,
                            child: MessageAlertSettingsPage(
                              sessionUnitId: controller.sessionUnitId,
                              title: controller.title,
                              isDialog: true,
                            ),
                          );
                        } else {
                          context.push(
                            '/chat/${Uri.encodeComponent(controller.sessionUnitId)}/notifications?title=${Uri.encodeQueryComponent(controller.title)}',
                          );
                        }
                      },
                    ),
                    if (controller.isGroup)
                      Cell(
                        icon: const Icon(
                          Icons.workspace_premium_outlined,
                          color: Colors.amber,
                        ),
                        title: '群主与管理员',
                        subtitle: _managersSummary(controller.members),
                        showArrow: true,
                        onTap: () => _openManagersViewerDialog(),
                      ),
                    if (controller.isGroup)
                      Cell(
                        icon: const Icon(Icons.account_tree_outlined),
                        title: '组织部门',
                        subtitle: '查看群组织架构',
                        showArrow: true,
                        onTap: controller.sessionId == null
                            ? null
                            : () => _openOrgViewerDialog(controller.sessionId!),
                      ),
                    if (controller.isGroup)
                      Cell(
                        icon: const Icon(Icons.campaign_outlined),
                        title: '群公告',
                        subtitle: '查看群公告',
                        showArrow: true,
                        onTap: controller.sessionId == null
                            ? null
                            : () {
                                AnnouncementListPage.open(
                                  context,
                                  sessionId: controller.sessionId!,
                                  canManage: controller.isCreator,
                                );
                              },
                      ),
                    if (controller.objectType == 2)
                      Cell(
                        icon: const Icon(Icons.admin_panel_settings_outlined),
                        title: '群管理',
                        subtitle:
                            (_roomMgmtSettings?.canEnterManagement ??
                                    controller.isCreator)
                                ? '设置、审核与权限'
                                : (_roomMgmtSettings?.canClaimCreator == true
                                    ? '暂无群主 · 点击认领'
                                    : '需管理权限'),
                        trailing:
                            (_roomMgmtSettings?.totalPendingCount ?? 0) > 0
                                ? Badge(
                                    label: Text(
                                      '${_roomMgmtSettings!.totalPendingCount}',
                                    ),
                                  )
                                : null,
                        showArrow: true,
                        onTap:
                            controller.sessionId == null
                                ? null
                                : () async {
                                    final canEnter =
                                        _roomMgmtSettings?.canEnterManagement ??
                                        controller.isCreator;
                                    if (!canEnter) {
                                      if (_roomMgmtSettings?.canClaimCreator ==
                                          true) {
                                        await _claimCreator(
                                          openManagementAfter: true,
                                        );
                                        return;
                                      }
                                      showToast(
                                        '需要群管理权限才能进入',
                                        type: ToastType.info,
                                      );
                                      return;
                                    }
                                    await _openGroupManagementCenter();
                                  },
                      ),
                    Cell(
                      icon: const Icon(Icons.notifications_off_outlined),
                      title: '免打扰',
                      switchValue: controller.isImmersed,
                      disabled: controller.updating,
                      onSwitchChanged:
                          controller.updating ? null : controller.setImmersed,
                    ),
                    Cell(
                      icon: const Icon(Icons.push_pin_outlined),
                      title: '置顶聊天',
                      switchValue: controller.isTopping,
                      disabled: controller.updating,
                      onSwitchChanged:
                          controller.updating ? null : controller.setTopping,
                    ),
                  ], title: '通知与管理'),
                  _section(<Widget>[
                    Cell(
                      icon: const Icon(
                        Icons.cleaning_services_outlined,
                        color: Colors.redAccent,
                      ),
                      title: '清空聊天记录',
                      titleColor: Colors.redAccent,
                      showArrow: true,
                      onTap: _confirmClear,
                    ),
                    Cell(
                      icon: const Icon(Icons.report_problem_outlined),
                      title: controller.isGroup ? '投诉该群' : '投诉',
                      showArrow: true,
                      onTap: () {
                        ReportDialog.showForGroup(
                          context,
                          groupId: controller.sessionUnitId,
                          groupTitle: controller.title,
                        );
                      },
                    ),
                    if (controller.isGroup)
                      Cell(
                        icon: Icon(
                          Icons.exit_to_app_rounded,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        title: '退出群聊',
                        titleColor: Theme.of(context).colorScheme.error,
                        showArrow: true,
                        onTap: _confirmExitGroup,
                      ),
                    if (controller.isOfficial)
                      Cell(
                        icon: Icon(
                          Icons.unsubscribe_outlined,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        title: '取消关注',
                        titleColor: Theme.of(context).colorScheme.error,
                        showArrow: true,
                        onTap: _confirmUnsubscribeOfficial,
                      ),
                  ], title: '操作'),
                ],
              ),
            ),
          ),
    );
  }

  Widget _section(List<Widget> children, {String? title}) =>
      CellGroup(title: title, children: children);

  String _managersSummary(List<ChatMember> members) {
    final owners = members.where((m) => m.isCreator).toList();
    final admins = members.where((m) => !m.isCreator && m.isAdmin).toList();
    if (_roomMgmtSettings?.canClaimCreator == true &&
        owners.isEmpty &&
        admins.isEmpty) {
      return '暂无群主 · 可成为群主';
    }
    if (owners.isNotEmpty && admins.isNotEmpty) {
      return '群主：${owners.first.name} · ${admins.length} 名管理员';
    }
    if (owners.isNotEmpty) {
      return '群主：${owners.first.name}';
    }
    if (admins.isNotEmpty) {
      return '${admins.length} 名管理员';
    }
    return '查看群主与管理员';
  }

  Future<void> _openGroupManagementCenter() async {
    if (controller.sessionId == null) return;
    final isDesktop =
        widget.isDrawer || MediaQuery.sizeOf(context).width >= 720;
    if (isDesktop) {
      await showDesktopModalDialog<void>(
        context: context,
        title: '群管理中心',
        subtitle: controller.title,
        width: 920,
        height: 680,
        child: GroupManagementPage(
          sessionId: controller.sessionId!,
          sessionUnitId: controller.sessionUnitId,
          ownerId: widget.ownerId,
          destinationId: controller.destinationId,
          isDialog: true,
        ),
      );
      await _loadRoomMgmtSettings();
      await controller.refresh();
    } else {
      final destQuery =
          controller.destinationId != null
              ? '&destinationId=${controller.destinationId}'
              : '';
      await context.push(
        '/group-management/${Uri.encodeComponent(controller.sessionId!)}?sessionUnitId=${Uri.encodeQueryComponent(controller.sessionUnitId)}&ownerId=${widget.ownerId}$destQuery',
      );
      await _loadRoomMgmtSettings();
    }
  }

  Future<void> _claimCreator({bool openManagementAfter = false}) async {
    final confirmed = await showConfirmModal(
      context: context,
      title: '成为群主',
      message: '当前群暂无群主和管理员，确认成为本群群主吗？成为群主后将拥有完整的群管理权限。',
      confirmText: '确认成为群主',
    );
    if (!confirmed || !mounted) return;
    try {
      final updated = await ref
          .read(groupManagementApiProvider)
          .claimCreator(widget.sessionUnitId);
      if (!mounted) return;
      setState(() => _roomMgmtSettings = updated);
      await controller.refresh();
      if (!mounted) return;
      showToast('您已成为本群群主', type: ToastType.success);
      if (openManagementAfter) {
        await _openGroupManagementCenter();
      }
    } catch (e) {
      if (mounted) {
        showToast('操作失败：$e', type: ToastType.error);
      }
    }
  }

  Future<void> _openManagersViewerDialog() async {
    await Future.wait(<Future<void>>[
      controller.refresh(),
      _loadRoomMgmtSettings(),
    ]);
    if (!mounted) return;
    final members = controller.members;
    final owners = members.where((m) => m.isCreator).toList();
    final admins = members.where((m) => !m.isCreator && m.isAdmin).toList();
    final canClaim = _roomMgmtSettings?.canClaimCreator == true;
    await showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('群主与管理员'),
            content: SizedBox(
              width: 380,
              height: 360,
              child: ListView(
                children: <Widget>[
                  if (canClaim)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          ctx,
                        ).colorScheme.primaryContainer.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: <Widget>[
                          const Expanded(
                            child: Text(
                              '当前群暂无群主和管理员，您可以成为本群群主。',
                              style: TextStyle(fontSize: 12.5),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _claimCreator();
                            },
                            child: const Text('成为群主'),
                          ),
                        ],
                      ),
                    ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      '群主',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (owners.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('暂未识别到群主信息'),
                    )
                  else
                    for (final owner in owners)
                      ListTile(
                        leading: ChatObjectAvatar(
                          name: owner.name,
                          imageUrl:
                              owner.avatarUrl.isEmpty ? null : owner.avatarUrl,
                          radius: 18,
                          chatObjectId: owner.chatObjectId,
                        ),
                        title: Text(owner.name),
                        trailing: const Chip(
                          label: Text(
                            '群主',
                            style: TextStyle(fontSize: 11, color: Colors.amber),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          MemberTile.showMemberDetails(context, owner);
                        },
                      ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      '管理员（${admins.length}）',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (admins.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('暂未设置群管理员'),
                    )
                  else
                    for (final admin in admins)
                      ListTile(
                        leading: ChatObjectAvatar(
                          name: admin.name,
                          imageUrl:
                              admin.avatarUrl.isEmpty ? null : admin.avatarUrl,
                          radius: 18,
                          chatObjectId: admin.chatObjectId,
                        ),
                        title: Text(admin.name),
                        trailing: const Chip(
                          label: Text(
                            '管理员',
                            style: TextStyle(fontSize: 11, color: Colors.blue),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          MemberTile.showMemberDetails(context, admin);
                        },
                      ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
            ],
          ),
    );
  }

  Future<void> _openOrgViewerDialog(String sessionId) async {
    List<IdNameItem> orgs = const <IdNameItem>[];
    Object? loadErr;
    try {
      orgs = await ref.read(groupManagementApiProvider).organizations(sessionId);
    } catch (e) {
      loadErr = e;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('群组织架构（只读）'),
            content: SizedBox(
              width: 380,
              height: 320,
              child:
                  loadErr != null
                      ? Center(child: Text('加载失败：$loadErr'))
                      : orgs.isEmpty
                      ? const Center(child: Text('当前群暂未配置组织部门'))
                      : ListView.builder(
                        itemCount: orgs.length,
                        itemBuilder:
                            (_, i) => ListTile(
                              leading: const Icon(Icons.account_tree_outlined),
                              title: Text(orgs[i].name),
                              subtitle: Text('ID: ${orgs[i].id}'),
                            ),
                      ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
            ],
          ),
    );
  }

  String? _avatarFor(SessionSummary friend) {
    final destination = friend.raw['destination'];
    if (destination is Map) {
      final value = destination['thumbnail'] ?? destination['portrait'];
      if (value != null && '$value'.isNotEmpty) return '$value';
    }
    return null;
  }

  Future<void> _editGroupName() async {
    if (widget.isDrawer) {
      final result = await showPromptModal(
        context: context,
        title: '修改群聊名称',
        initialValue: controller.title,
        placeholderText: '群聊名称',
        confirmText: '保存',
      );
      if (result != null && result.trim().isNotEmpty && mounted) {
        try {
          await controller.setGroupName(result.trim());
          showToast('群聊名称已更新', type: ToastType.success);
          await controller.initialize();
        } catch (e) {
          showToast('修改失败：$e', type: ToastType.error);
        }
      }
      return;
    }

    final updated = await context.push<bool>(
      '/chat/${Uri.encodeComponent(controller.sessionUnitId)}/group-name?ownerId=${controller.ownerId}&title=${Uri.encodeQueryComponent(controller.title)}',
    );
    if (updated == true && mounted) {
      await controller.initialize();
    }
  }

  Future<void> _editRename() async {
    final isGroup = controller.objectType == 2;
    final result = await showPromptModal(
      context: context,
      title: isGroup ? '修改我在本群的昵称' : '设置备注',
      initialValue: controller.rename,
      placeholderText: isGroup ? '群内昵称' : '备注名',
      confirmText: '保存',
    );
    if (result != null && mounted) {
      try {
        await controller.setRename(result.trim());
        showToast('备注已更新', type: ToastType.success);
      } catch (e) {
        showToast('更新失败：$e', type: ToastType.error);
      }
    }
  }

  Future<void> _previewCurrentBackground(String bgUrl) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ChatBackgroundPreviewPage(
          controller: controller,
          chatTitle: controller.title,
          currentImageUrl: bgUrl,
        ),
      ),
    );
    if (result == true && mounted) {
      await controller.refresh();
      setState(() {});
    }
  }

  Future<void> _openBackgroundSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChatBackgroundPage(
          controller: controller,
        ),
      ),
    );
    if (mounted) {
      await controller.refresh();
      setState(() {});
    }
  }

  Future<void> _confirmClearBackground() async {
    final confirmed = await showConfirmModal(
      context: context,
      title: '删除聊天背景',
      message: '确定要删除当前聊天背景并恢复默认吗？',
      confirmText: '确认删除',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await controller.clearBackgroundImage();
      if (mounted) {
        showToast('聊天背景已删除', type: ToastType.success);
        await controller.refresh();
        setState(() {});
      }
    } catch (error) {
      if (mounted) {
        showToast('删除背景失败：$error', type: ToastType.error);
      }
    }
  }

  Future<void> _confirmClear() async {
    final confirmed = await showConfirmModal(
      context: context,
      title: '清空聊天记录',
      message: '将同时清除服务器和本机保存的该会话消息，确定继续吗？',
      confirmText: '清空',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await controller.clearMessages();
      widget.onMessagesCleared?.call();
      if (mounted) Navigator.pop(context, ChatSettingsResult.messagesCleared);
    } catch (error) {
      if (mounted) {
        showToast('清空失败：$error', type: ToastType.error);
      }
    }
  }

  Future<void> _confirmExitGroup() async {
    final confirmed = await showConfirmModal(
      context: context,
      title: '退出群聊',
      message: '退出后将不再接收该群的新消息，确定退出吗？',
      confirmText: '退出',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await controller.exitChat();
      widget.onSessionLeft?.call();
      if (mounted) Navigator.pop(context, ChatSettingsResult.sessionLeft);
    } catch (error) {
      if (mounted) showToast('退出群聊失败：$error', type: ToastType.error);
    }
  }

  Future<void> _confirmUnsubscribeOfficial() async {
    final confirmed = await showConfirmModal(
      context: context,
      title: '取消关注',
      message: '取消关注后将不再接收该公众号的新消息，确定继续吗？',
      confirmText: '取消关注',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await controller.unsubscribeOfficial();
      widget.onSessionLeft?.call();
      if (mounted) Navigator.pop(context, ChatSettingsResult.sessionLeft);
    } catch (error) {
      if (mounted) showToast('取消关注失败：$error', type: ToastType.error);
    }
  }
}

class _MemberPreview extends StatelessWidget {
  const _MemberPreview({required this.controller});
  final ChatSettingsController controller;

  @override
  Widget build(BuildContext context) => GlassCard(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
    child: Column(
      children: <Widget>[
        if (controller.loading && controller.members.isEmpty)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              childAspectRatio: .72,
              mainAxisSpacing: 4,
            ),
            itemCount: 10,
            itemBuilder: (context, _) {
              final skColor = Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.14);
              return Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: skColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 36,
                    height: 10,
                    decoration: BoxDecoration(
                      color: skColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              );
            },
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              childAspectRatio: .72,
              mainAxisSpacing: 4,
            ),
            itemCount: controller.members.length,
            itemBuilder:
                (context, index) => MemberTile(
                  member: controller.members[index],
                  compact: true,
                ),
          ),
        if (controller.totalCount > 0 || controller.isGroup)
          TextButton(
            onPressed: () {
              final isDesktop = MediaQuery.sizeOf(context).width >= 720;
              if (isDesktop) {
                showDesktopModalDialog<void>(
                  context: context,
                  title: '群聊成员',
                  subtitle: controller.title,
                  width: 500,
                  height: 600,
                  child: MemberListPage(
                    ownerId: controller.ownerId,
                    sessionUnitId: controller.sessionUnitId,
                    initialTotalCount: controller.totalCount,
                    isDialog: true,
                  ),
                );
              } else {
                context.push(
                  '/chat/${Uri.encodeComponent(controller.sessionUnitId)}/members'
                  '?ownerId=${controller.ownerId}&totalCount=${controller.totalCount}',
                );
              }
            },
            child: Text(
              controller.totalCount > 0
                  ? '查看更多（${controller.totalCount}）'
                  : '查看全部群成员',
            ),
          ),
      ],
    ),
  );
}
