import 'package:flutter/material.dart';

class PinnedDividerItem extends StatelessWidget {
  const PinnedDividerItem({
    required this.count,
    required this.hasMore,
    super.key,
  });
  final int count;
  final bool hasMore;
  @override
  Widget build(BuildContext context) => _DividerRow(
    icon: Icons.menu_open,
    text: '以上是置顶会话',
    count: count,
    hasMore: hasMore,
  );
}

class TimeDividerItem extends StatelessWidget {
  const TimeDividerItem({
    required this.text,
    required this.count,
    required this.hasMore,
    super.key,
  });
  final String text;
  final int count;
  final bool hasMore;
  @override
  Widget build(BuildContext context) => _DividerRow(
    icon: Icons.drag_handle,
    text: text,
    count: count,
    hasMore: hasMore,
  );
}

class _DividerRow extends StatelessWidget {
  const _DividerRow({
    required this.icon,
    required this.text,
    required this.count,
    required this.hasMore,
  });
  final IconData icon;
  final String text;
  final int count;
  final bool hasMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      color: colorScheme.surfaceContainerLowest,
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(
            icon,
            size: 15,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 8),
          Text(
            '$text (${hasMore ? '$count+' : count})',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
