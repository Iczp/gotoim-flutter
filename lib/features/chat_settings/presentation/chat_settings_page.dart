import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:image_picker/image_picker.dart';

import '../../../core/widgets/app_modal.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/cell_group.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/network/api_client.dart';
import '../../session/application/session_list_controller.dart';
import '../../session/data/models/session_summary.dart';
import '../../session/presentation/chat_object_avatar.dart';
import '../../user/presentation/profile_page.dart';
import '../application/chat_settings_controller.dart';
import 'member_tile.dart';

enum ChatSettingsResult { messagesCleared, sessionLeft }

class ChatSettingsPage extends ConsumerStatefulWidget {
  const ChatSettingsPage({
    required this.ownerId,
    required this.sessionUnitId,
    super.key,
  });
  final int ownerId;
  final String sessionUnitId;

  @override
  ConsumerState<ChatSettingsPage> createState() => _ChatSettingsPageState();
}

class _ChatSettingsPageState extends ConsumerState<ChatSettingsPage> {
  late final ChatSettingsController controller;

  @override
  void initState() {
    super.initState();
    controller = ChatSettingsController(
      ref.read(chatSettingsRepositoryProvider),
      ref.read(sessionRepositoryProvider),
      ownerId: widget.ownerId,
      sessionUnitId: widget.sessionUnitId,
    )..initialize();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder:
        (context, _) => Scaffold(
          appBar: AppBar(title: const Text('聊天设置')),
          body: RefreshIndicator(
            onRefresh: controller.refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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

                // ── 成员预览卡片 ─────────────────────────────────────
                GlassCard(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                  child: _MemberPreview(controller: controller),
                ),

                // ── 会话信息 ─────────────────────────────────────────
                if (controller.friend != null)
                  CellGroup(
                    title: '会话信息',
                    children: <Widget>[
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
                        onTap: () => openProfilePage(
                          context,
                          subject: ProfileSubject.session(controller.friend!),
                        ),
                      ),
                    ],
                  ),

                // ── 聊天设置 ─────────────────────────────────────────
                CellGroup(
                  title: '聊天设置',
                  children: <Widget>[
                    Cell(
                      title: '类型',
                      value: controller.objectTypeLabel,
                    ),
                    if (controller.objectType == 2)
                      Cell(
                        title: '群名称',
                        value: controller.title,
                        showArrow: true,
                        onTap: _editGroupName,
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
                  ],
                ),

                // ── 功能 ─────────────────────────────────────────────
                CellGroup(
                  title: '功能',
                  children: <Widget>[
                    Cell(
                      icon: const Icon(Icons.search),
                      title: '查找聊天记录',
                      showArrow: true,
                    ),
                    Cell(
                      icon: const Icon(Icons.wallpaper_rounded),
                      title: '设置聊天背景',
                      showArrow: true,
                      trailing:
                          (controller.backgroundImage ?? '').isNotEmpty
                              ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  IconButton(
                                    tooltip: '取消背景',
                                    onPressed: _confirmClearBackground,
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                    ),
                                    iconSize: 20,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.chevron_right, size: 18),
                                ],
                              )
                              : null,
                      onTap: _changeBackground,
                    ),
                  ],
                ),

                // ── 通知 ─────────────────────────────────────────────
                CellGroup(
                  title: '通知',
                  children: <Widget>[
                    Cell(
                      icon: const Icon(Icons.notifications_active_outlined),
                      title: '消息提醒',
                      subtitle: '本会话的通知、声音、振动与消息预览',
                      showArrow: true,
                      onTap: () => context.push(
                        '/chat/${Uri.encodeComponent(controller.sessionUnitId)}/notifications?title=${Uri.encodeQueryComponent(controller.title)}',
                      ),
                    ),
                    if (controller.objectType == 2)
                      Cell(
                        icon: const Icon(Icons.admin_panel_settings_outlined),
                        title: '群管理',
                        subtitle: '组织部门、角色与权限',
                        showArrow: true,
                        onTap:
                            controller.sessionId == null
                                ? null
                                : () => context.push(
                                  '/group-management/${Uri.encodeComponent(controller.sessionId!)}',
                                ),
                      ),
                    Cell(
                      title: '免打扰',
                      switchValue: controller.isImmersed,
                      onSwitchChanged:
                          controller.updating ? null : controller.setImmersed,
                    ),
                    Cell(
                      title: '置顶聊天',
                      switchValue: controller.isTopping,
                      onSwitchChanged:
                          controller.updating ? null : controller.setTopping,
                    ),
                  ],
                ),

                // ── 其他（危险操作）──────────────────────────────────
                CellGroup(
                  title: '其他',
                  children: <Widget>[
                    Cell(
                      title: '清空聊天记录',
                      titleColor: Colors.red,
                      showArrow: true,
                      onTap: _confirmClear,
                    ),
                    const Cell(title: '投诉', showArrow: true),
                    if (controller.isGroup)
                      Cell(
                        title: '退出群聊',
                        titleColor: Theme.of(context).colorScheme.error,
                        showArrow: true,
                        onTap: _confirmExitGroup,
                      ),
                    if (controller.isOfficial)
                      Cell(
                        title: '取消关注',
                        titleColor: Theme.of(context).colorScheme.error,
                        showArrow: true,
                        onTap: _confirmUnsubscribeOfficial,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
  );

  String? _avatarFor(SessionSummary friend) {
    final destination = friend.raw['destination'];
    if (destination is Map) {
      final value = destination['thumbnail'] ?? destination['portrait'];
      if (value != null && '$value'.isNotEmpty) return '$value';
    }
    return null;
  }

  Future<void> _editGroupName() async {
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

  Future<void> _changeBackground() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null && mounted) {
      try {
        await controller.setBackgroundImage(
          MultipartUploadFile(
            name: picked.name,
            length: await picked.length(),
            openRead: picked.openRead,
          ),
        );
        showToast('聊天背景已设置', type: ToastType.success);
      } catch (e) {
        showToast('设置背景失败：$e', type: ToastType.error);
      }
    }
  }

  Future<void> _confirmClearBackground() async {
    final confirmed = await showConfirmModal(
      context: context,
      title: '取消聊天背景',
      message: '将恢复默认聊天背景，确定继续吗？',
      confirmText: '取消背景',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await controller.clearBackgroundImage();
      if (mounted) {
        showToast('聊天背景已取消', type: ToastType.success);
      }
    } catch (error) {
      if (mounted) {
        showToast('取消背景失败：$error', type: ToastType.error);
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
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      if (controller.loading && controller.members.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        )
      else
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5,
            childAspectRatio: .78,
            mainAxisSpacing: 4,
          ),
          itemCount: controller.members.length,
          itemBuilder:
              (context, index) => MemberTile(
                member: controller.members[index],
                compact: true,
              ),
        ),
      TextButton(
        onPressed:
            controller.totalCount == 0
                ? null
                : () => context.push(
                  '/chat/${Uri.encodeComponent(controller.sessionUnitId)}/members'
                  '?ownerId=${controller.ownerId}',
                ),
        child: Text('查看更多（${controller.totalCount}）'),
      ),
    ],
  );
}
