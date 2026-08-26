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
  Widget build(BuildContext context) => Container(
    color: Theme.of(context).colorScheme.surfaceContainerLowest,
    height: 30,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 8),
        Text(
          '$text (${hasMore ? '$count+' : count})',
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: Colors.grey),
        ),
      ],
    ),
  );
}
