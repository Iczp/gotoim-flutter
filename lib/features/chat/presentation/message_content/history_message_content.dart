import 'package:flutter/material.dart';

import '../../../../core/utils/api_url_resolver.dart';
import '../../data/models/chat_message.dart';
import 'chat_message_presentation.dart';
import 'message_bubble.dart';

class HistoryMessageContent extends StatelessWidget {
  const HistoryMessageContent({
    required this.message,
    this.presentation = ChatMessagePresentation.normal,
    this.rootMessageId,
    super.key,
  });

  final ChatMessage message;
  final ChatMessagePresentation presentation;
  final int? rootMessageId;

  /// 为聊天记录内子消息附件统一补全 `su`、`msg` 与外层可见 `rootMsg` 授权参数。
  String resolveChildAttachmentUrl(
    String? rawUrl,
    String apiBaseUrl, {
    int? childMessageId,
    String? childSessionUnitId,
  }) => resolveAttachmentUrl(
    rawUrl,
    apiBaseUrl,
    sessionUnitId:
        (childSessionUnitId?.trim().isNotEmpty == true)
            ? childSessionUnitId
            : message.sessionUnitId,
    messageId: childMessageId,
    rootMessageId: rootMessageId ?? message.serverId,
  );

  @override
  Widget build(BuildContext context) {
    final compact = presentation == ChatMessagePresentation.quote;
    final card = SizedBox(
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

    if (compact) {
      return card;
    }

    return MessageBubble(
      message: message,
      child: card,
    );
  }
}
