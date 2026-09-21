import 'package:flutter/material.dart';

/// Bottom action bar shown while the user is selecting multiple messages.
/// It is deliberately presentation-only; selection state remains in
/// [ChatController].
class ChatSelectionBar extends StatelessWidget {
  const ChatSelectionBar({
    required this.count,
    required this.onCancel,
    required this.onDelete,
    required this.onMergeForward,
    super.key,
  });

  final int count;
  final VoidCallback onCancel;
  final VoidCallback onDelete;
  final VoidCallback onMergeForward;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Material(
      elevation: 8,
      child: SizedBox(
        height: 56,
        child: Row(
          children: <Widget>[
            IconButton(
              tooltip: '取消多选',
              onPressed: onCancel,
              icon: const Icon(Icons.close),
            ),
            Expanded(child: Text('已选择 $count 条')),
            IconButton(
              tooltip: '合并转发',
              onPressed: count == 0 ? null : onMergeForward,
              icon: const Icon(Icons.reply_all_outlined),
            ),
            IconButton(
              tooltip: '删除所选消息',
              onPressed: count == 0 ? null : onDelete,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    ),
  );
}
