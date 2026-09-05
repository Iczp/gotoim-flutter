import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../application/session_list_controller.dart';
import '../data/models/session_summary.dart';
import 'chat_object_avatar.dart';

enum SessionMenuAction { topping, notification, settings, clear }

/// Modal bottom sheet for session long-press actions.
class SessionMenuSheet extends StatelessWidget {
  const SessionMenuSheet({
    required this.session,
    super.key,
  });

  final SessionSummary session;

  static Future<void> show({
    required BuildContext context,
    required SessionListController controller,
    required SessionSummary session,
  }) async {
    final action = await showModalBottomSheet<SessionMenuAction>(
      context: context,
      useRootNavigator: true,
      isDismissible: true,
      enableDrag: true,
      barrierColor: Colors.black54,
      showDragHandle: true,
      builder: (_) => SessionMenuSheet(session: session),
    );
    if (action == null || !context.mounted) return;

    if (action == SessionMenuAction.settings) {
      await context.push(
        '/chat/${Uri.encodeComponent(session.id)}/settings'
        '?ownerId=${session.ownerId ?? controller.currentOwner?.id ?? 0}',
      );
      return;
    }

    if (action == SessionMenuAction.clear) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: const Text('清空聊天记录'),
              content: Text('确定清空“${session.title}”的全部聊天记录吗？'),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('清空'),
                ),
              ],
            ),
      );
      if (confirmed != true || !context.mounted) return;
    }

    try {
      switch (action) {
        case SessionMenuAction.topping:
          await controller.setTopping(session, !session.isPinned);
        case SessionMenuAction.notification:
          await controller.setImmersed(session, !session.isImmersed);
        case SessionMenuAction.clear:
          await controller.clearMessages(session);
        case SessionMenuAction.settings:
          break;
      }
      if (context.mounted) {
        final message = switch (action) {
          SessionMenuAction.topping => session.isPinned ? '已取消置顶' : '已置顶',
          SessionMenuAction.notification =>
            session.isImmersed ? '已开启消息通知' : '已关闭消息通知',
          SessionMenuAction.clear => '聊天记录已清空',
          SessionMenuAction.settings => '',
        };
        if (message.isNotEmpty) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        }
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('操作失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(
            leading: ChatObjectAvatar(
              name: session.title,
              imageUrl: null,
              radius: 22,
            ),
            title: Text(
              session.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: const Text('会话操作'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(
              session.isPinned
                  ? Icons.push_pin_outlined
                  : Icons.push_pin_rounded,
            ),
            title: Text(session.isPinned ? '取消置顶' : '置顶会话'),
            onTap: () => Navigator.pop(context, SessionMenuAction.topping),
          ),
          ListTile(
            leading: Icon(
              session.isImmersed
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_off_outlined,
            ),
            title: Text(session.isImmersed ? '开启消息通知' : '关闭消息通知'),
            onTap: () => Navigator.pop(context, SessionMenuAction.notification),
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('聊天设置'),
            onTap: () => Navigator.pop(context, SessionMenuAction.settings),
          ),
          ListTile(
            leading: Icon(
              Icons.delete_sweep_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              '清空聊天记录',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            onTap: () => Navigator.pop(context, SessionMenuAction.clear),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
