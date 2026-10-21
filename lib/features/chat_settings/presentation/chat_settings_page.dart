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
import '../../group_management/presentation/group_management_page.dart';
import '../application/chat_settings_controller.dart';
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
                    if (controller.objectType == 2)
                      Cell(
                        icon: const Icon(Icons.admin_panel_settings_outlined),
                        title: '群管理',
                        subtitle: '组织部门、角色与权限',
                        showArrow: true,
                        onTap:
                            controller.sessionId == null
                                ? null
                                : () {
                                    final isDesktop =
                                        widget.isDrawer ||
                                        MediaQuery.sizeOf(context).width >= 720;
                                    if (isDesktop) {
                                      showDesktopModalDialog<void>(
                                        context: context,
                                        title: '群管理',
                                        subtitle: controller.title,
                                        width: 580,
                                        height: 620,
                                        child: GroupManagementPage(
                                          sessionId: controller.sessionId!,
                                          isDialog: true,
                                        ),
                                      );
                                    } else {
                                      context.push(
                                        '/group-management/${Uri.encodeComponent(controller.sessionId!)}',
                                      );
                                    }
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
