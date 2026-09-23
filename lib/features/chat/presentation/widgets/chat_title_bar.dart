import 'package:flutter/material.dart';

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
    this.hasBackground = false,
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
  final bool hasBackground;

  static const double toolbarHeight = 48;

  @override
  Size get preferredSize => const Size.fromHeight(toolbarHeight);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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

    final titleStyle = TextStyle(
      fontSize: 16.5,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
      color:
          isDark
              ? const Color(0xFFF1F5F9)
              : (hasBackground
                  ? const Color(0xFF0F172A)
                  : const Color(0xFF1E293B)),
    );

    final titleWidget = Text(
      title,
      style: titleStyle,
      overflow: TextOverflow.ellipsis,
    );

    if (useGlass) {
      final Color glassBackground;
      final Color glassBorder;
      final double blurSigma = hasBackground ? 18.0 : 20.0;

      if (hasBackground) {
        glassBackground =
            isDark
                ? const Color(0xFF0B1120).withValues(alpha: 0.74)
                : Colors.white.withValues(alpha: 0.72);
        glassBorder =
            isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06);
      } else {
        glassBackground =
            isDark
                ? const Color(0xFF0B1120).withValues(alpha: 0.88)
                : Colors.white.withValues(alpha: 0.88);
        glassBorder =
            isDark
                ? const Color(0xFF1E293B).withValues(alpha: 0.8)
                : const Color(0xFFE2E8F0).withValues(alpha: 0.8);
      }

      return GlassAppBar(
        leading: leading,
        title: titleWidget,
        actions: actions,
        blurSigma: blurSigma,
        backgroundColor: glassBackground,
        borderColor: glassBorder,
        borderWidth: 0.8,
        centerTitle: false,
      );
    }

    return AppBar(
      leading: leading,
      title: titleWidget,
      actions: actions,
      elevation: 0,
      scrolledUnderElevation: 0,
    );
  }
}
