import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/widgets/glass_container.dart';

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
    this.onOpenAiRuns,
    this.selectionMode = false,
    this.onCancelSelection,
    this.useGlass = false,
    super.key,
  });

  final String title;
  final bool showTransfer;
  final VoidCallback onTransfer;
  final VoidCallback onOpenSettings;
  final VoidCallback? onOpenAiRuns;
  final bool selectionMode;
  final VoidCallback? onCancelSelection;
  final bool useGlass;

  static const double toolbarHeight = 48;

  @override
  Size get preferredSize => const Size.fromHeight(toolbarHeight);

  @override
  Widget build(BuildContext context) {
    final leading =
        selectionMode
            ? IconButton(
              tooltip: '取消',
              icon: const Icon(Icons.close),
              onPressed: onCancelSelection ?? () => Navigator.maybePop(context),
            )
            : null;
    final actions = <Widget>[
      if (!selectionMode && onOpenAiRuns != null)
        IconButton(
          tooltip: 'AI 运行记录',
          onPressed: onOpenAiRuns,
          icon: const Icon(Icons.timeline_outlined),
        ),
      if (showTransfer && !selectionMode)
        IconButton(
          tooltip: '转接',
          onPressed: onTransfer,
          icon: const Icon(Icons.electrical_services_outlined),
        ),
      if (!selectionMode)
        IconButton(
          tooltip: '聊天设置',
          onPressed: onOpenSettings,
          icon: const Icon(Icons.more_horiz),
        ),
    ];
    final titleWidget = Text(title, overflow: TextOverflow.ellipsis);

    if (useGlass) {
      final tokens = context.appTokens;
      return GlassAppBar(
        leading: leading,
        title: titleWidget,
        actions: actions,
        blurSigma: tokens.chatGlassBlurSigma,
        backgroundColor: tokens.glassSurfaceColor.withValues(
          alpha: tokens.chatTitleGlassOpacity,
        ),
        borderColor: tokens.glassBorderColor.withValues(
          alpha: tokens.chatGlassBorderOpacity,
        ),
        centerTitle: false,
      );
    }

    return AppBar(leading: leading, title: titleWidget, actions: actions);
  }
}
