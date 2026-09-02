import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 头像上下文菜单项。
class ChatAvatarMenuItem {
  const ChatAvatarMenuItem({
    required this.id,
    required this.label,
    required this.icon,
    this.destructive = false,
    this.onTap,
  });

  final String id;
  final String label;
  final IconData icon;
  final bool destructive;
  final FutureOr<void> Function()? onTap;
}

/// 聊天窗口头像竖排菜单组件（图标 - 文字，底部带分割线）。
class ChatAvatarMenu extends StatelessWidget {
  const ChatAvatarMenu({
    required this.items,
    this.width = 148,
    super.key,
  });

  final List<ChatAvatarMenuItem> items;
  final double width;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: isDark
              ? theme.colorScheme.surfaceContainerHighest
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.dividerColor.withValues(alpha: 0.15),
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              _buildItemTile(context, theme, items[i]),
              if (i < items.length - 1)
                Divider(
                  height: 1,
                  thickness: 0.5,
                  indent: 14,
                  endIndent: 14,
                  color: theme.dividerColor.withValues(alpha: 0.2),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildItemTile(
    BuildContext context,
    ThemeData theme,
    ChatAvatarMenuItem item,
  ) {
    final color = item.destructive
        ? theme.colorScheme.error
        : theme.colorScheme.onSurface;

    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        item.onTap?.call();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Icon(
              item.icon,
              size: 18,
              color: color,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
