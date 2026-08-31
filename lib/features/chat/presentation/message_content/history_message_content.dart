import 'package:flutter/material.dart';

import '../../data/models/chat_message.dart';
import 'chat_message_presentation.dart';

class HistoryMessageContent extends StatelessWidget {
  const HistoryMessageContent({
    required this.message,
    this.presentation = ChatMessagePresentation.normal,
    super.key,
  });

  final ChatMessage message;
  final ChatMessagePresentation presentation;

  @override
  Widget build(BuildContext context) {
    final compact = presentation == ChatMessagePresentation.quote;
    return SizedBox(
      width: compact ? null : 240,
      child: Row(
        children: <Widget>[
          Icon(Icons.forum_outlined, size: compact ? 19 : 28),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  message.historyTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (!compact && message.historyDescription.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      message.historyDescription,
                      maxLines: 2,
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
