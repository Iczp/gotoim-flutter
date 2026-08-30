import 'package:flutter/material.dart';

/// The chat page's title and its page-level actions.
///
/// It deliberately receives callbacks instead of a [ChatController], keeping
/// navigation and call-center concerns in the page coordinator.
class ChatTitleBar extends StatelessWidget implements PreferredSizeWidget {
  const ChatTitleBar({
    required this.title,
    required this.showTransfer,
    required this.onTransfer,
    required this.onOpenSettings,
    super.key,
  });

  final String title;
  final bool showTransfer;
  final VoidCallback onTransfer;
  final VoidCallback onOpenSettings;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) => AppBar(
    title: Text(title, overflow: TextOverflow.ellipsis),
    actions: <Widget>[
      if (showTransfer)
        IconButton(
          tooltip: '转接',
          onPressed: onTransfer,
          icon: const Icon(Icons.electrical_services_outlined),
        ),
      IconButton(
        tooltip: '聊天设置',
        onPressed: onOpenSettings,
        icon: const Icon(Icons.more_horiz),
      ),
    ],
  );
}
