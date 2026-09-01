import 'package:flutter/material.dart';

import '../data/models/chat_owner.dart';
import 'chat_object_avatar.dart';

/// Header displaying the current chat identity / owner with transparent background.
class CurrentOwnerHeader extends StatelessWidget {
  const CurrentOwnerHeader({
    required this.owner,
    required this.hasMultiple,
    required this.isConnecting,
    required this.onPressed,
    super.key,
  });

  final ChatOwner? owner;
  final bool hasMultiple;
  final bool isConnecting;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              ChatObjectAvatar(
                name: owner?.name ?? '-',
                imageUrl: owner?.imageUrl,
                radius: 18,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  owner?.name ?? 'Goto IM',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (hasMultiple)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
