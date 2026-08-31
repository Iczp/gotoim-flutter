import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/models/chat_message.dart';

class ChatMessageMenuItem {
  const ChatMessageMenuItem({
    required this.id,
    required this.label,
    required this.icon,
    this.enabled = true,
    this.destructive = false,
    this.onTap,
  });
  final String id;
  final String label;
  final IconData icon;
  final bool enabled;
  final bool destructive;
  final FutureOr<void> Function()? onTap;
}

class ChatMessageMenuContext {
  const ChatMessageMenuContext({
    required this.message,
    this.canRecall = false,
    this.canDelete = true,
    this.canRetry = false,
    this.onAction,
  });
  final ChatMessage message;
  final bool canRecall;
  final bool canDelete;
  final bool canRetry;
  final FutureOr<void> Function(String id, ChatMessage message)? onAction;
}

class ChatMessageMenuBuilder {
  const ChatMessageMenuBuilder();
  List<ChatMessageMenuItem> build(ChatMessageMenuContext context) {
    final message = context.message;
    if (message.messageType == 1) {
      return const [];
    }
    if (message.isRollbacked) {
      return context.canDelete
          ? [
            _item(
              'delete',
              '删除',
              Icons.delete_outline,
              context,
              destructive: true,
            ),
          ]
          : const [];
    }
    if (message.state == 'failed') {
      return [
        if (context.canRetry) _item('retry', '重新发送', Icons.refresh, context),
        if (context.canDelete)
          _item(
            'delete',
            '删除',
            Icons.delete_outline,
            context,
            destructive: true,
          ),
      ];
    }
    if (message.state == 'sending') {
      return context.canDelete
          ? [
            _item(
              'delete',
              '删除',
              Icons.delete_outline,
              context,
              destructive: true,
            ),
          ]
          : const [];
    }
    final items = <ChatMessageMenuItem>[
      _item('reply', '回复', Icons.reply_outlined, context),
      if (message.messageType == 0 && message.text.isNotEmpty)
        _item('copy', '复制', Icons.copy_outlined, context),
      _item('forward', '转发', Icons.forward_outlined, context),
    ];
    if (message.isMine && context.canRecall) {
      items.add(_item('recall', '撤回', Icons.undo_outlined, context));
    }
    if (context.canDelete) {
      items.add(
        _item('delete', '删除', Icons.delete_outline, context, destructive: true),
      );
    }
    return items;
  }

  ChatMessageMenuItem _item(
    String id,
    String label,
    IconData icon,
    ChatMessageMenuContext context, {
    bool destructive = false,
  }) => ChatMessageMenuItem(
    id: id,
    label: label,
    icon: icon,
    destructive: destructive,
    onTap: () => context.onAction?.call(id, context.message),
  );
}

class ChatMessageMenu extends StatelessWidget {
  const ChatMessageMenu({required this.items, super.key});
  final List<ChatMessageMenuItem> items;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 2,
    runSpacing: 2,
    children:
        items
            .map(
              (item) => TextButton.icon(
                onPressed: item.enabled ? () => item.onTap?.call() : null,
                icon: Icon(
                  item.icon,
                  size: 18,
                  color:
                      item.destructive
                          ? Theme.of(context).colorScheme.error
                          : null,
                ),
                label: Text(
                  item.label,
                  style:
                      item.destructive
                          ? TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          )
                          : null,
                ),
              ),
            )
            .toList(),
  );
}
