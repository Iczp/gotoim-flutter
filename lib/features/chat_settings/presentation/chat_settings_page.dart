import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:image_picker/image_picker.dart';

import '../../../core/widgets/app_modal.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/cell_group.dart';
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
                const SizedBox(height: 10),
                if (controller.friend != null) ...<Widget>[
                  _section(<Widget>[
                    ListTile(
                      leading: ChatObjectAvatar(
                        name: controller.friend!.title,
                        imageUrl: _avatarFor(controller.friend!),
                        radius: 23,
                        chatObjectId: controller.friend!.destinationId,
                      ),
                      title: Text(
                        controller.objectType == 2 ? '查看群资料' : '查看好友资料',
                      ),
                      subtitle: Text(controller.friend!.title),
                      trailing: const Icon(Icons.chevron_right),
                      onTap:
                          () => openProfilePage(
                            context,
                            subject: ProfileSubject.session(controller.friend!),
                          ),
                    ),
                  ], title: '会话信息'),
                  const SizedBox(height: 10),
                ],
                _section(<Widget>[
                  ListTile(
                    title: const Text('类型'),
                    trailing: Text(controller.objectTypeLabel),
                  ),
                  if (controller.objectType == 2)
                    ListTile(
                      title: const Text('群名称'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 180),
                            child: Text(
                              controller.title,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                      onTap: _editGroupName,
                    ),
                  ListTile(
                    title: Text(
                      controller.objectType == 2 ? '我在本群的昵称' : '设置备注',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 180),
                          child: Text(
                            controller.rename.isNotEmpty
                                ? controller.rename
                                : '未设置',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color:
                                  controller.rename.isNotEmpty
                                      ? null
                                      : Theme.of(context).disabledColor,
                            ),
                          ),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: _editRename,
                  ),
                ], title: '聊天设置'),
                const SizedBox(height: 10),
                _section(<Widget>[
                  const ListTile(
                    leading: Icon(Icons.search),
                    title: Text('查找聊天记录'),
                    trailing: Icon(Icons.chevron_right),
                  ),
                  ListTile(
                    leading: const Icon(Icons.wallpaper_rounded),
                    title: const Text('设置聊天背景'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _changeBackground,
                  ),
                ], title: '功能'),
                const SizedBox(height: 10),
                _section(<Widget>[
                  ListTile(
                    leading: const Icon(Icons.notifications_active_outlined),
                    title: const Text('消息提醒'),
                    subtitle: const Text('本会话的通知、声音、振动与消息预览'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap:
                        () => context.push(
                          '/chat/${Uri.encodeComponent(controller.sessionUnitId)}/notifications?title=${Uri.encodeQueryComponent(controller.title)}',
                        ),
                  ),
                  if (controller.objectType == 2)
                    ListTile(
                      leading: const Icon(Icons.admin_panel_settings_outlined),
                      title: const Text('群管理'),
                      subtitle: const Text('组织部门、角色与权限'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap:
                          controller.sessionId == null
                              ? null
                              : () => context.push(
                                '/group-management/${Uri.encodeComponent(controller.sessionId!)}',
                              ),
                    ),
                  SwitchListTile(
                    title: const Text('免打扰'),
                    value: controller.isImmersed,
                    onChanged:
                        controller.updating ? null : controller.setImmersed,
                  ),
                  SwitchListTile(
                    title: const Text('置顶聊天'),
                    value: controller.isTopping,
                    onChanged:
                        controller.updating ? null : controller.setTopping,
                  ),
                ], title: '通知'),
                const SizedBox(height: 10),
                _section(<Widget>[
                  ListTile(
                    title: const Text(
                      '清空聊天记录',
                      style: TextStyle(color: Colors.red),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _confirmClear,
                  ),
                  const ListTile(
                    title: Text('投诉'),
                    trailing: Icon(Icons.chevron_right),
                  ),
                  if (controller.isGroup)
                    ListTile(
                      title: Text(
                        '退出群聊',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _confirmExitGroup,
                    ),
                  if (controller.isOfficial)
                    ListTile(
                      title: Text(
                        '取消关注',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _confirmUnsubscribeOfficial,
                    ),
                ], title: '其他'),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
  );

  Widget _section(List<Widget> children, {String? title}) => CellGroup(
    title: title,
    margin: const EdgeInsets.only(bottom: 10),
    children: children,
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
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
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
      ),
    ),
  );
}
