import 'package:flutter/material.dart';

import 'chat_message_presentation.dart';

class BasicMessageCard extends StatelessWidget {
  const BasicMessageCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.presentation,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final ChatMessagePresentation presentation;

  @override
  Widget build(BuildContext context) {
    final compact = presentation == ChatMessagePresentation.quote;
    return SizedBox(
      width: compact ? null : 240,
      child: Row(
        children: <Widget>[
          Container(
            width: compact ? 32 : 48,
            height: compact ? 32 : 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: compact ? 18 : 26),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (subtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      subtitle,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
