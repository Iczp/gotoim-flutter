import 'package:flutter/material.dart';

import '../../../../core/utils/api_url_resolver.dart';
import '../../data/models/chat_message.dart';
import 'chat_message_presentation.dart';
import 'message_bubble.dart';

class LinkMessageContent extends StatelessWidget {
  const LinkMessageContent({
    required this.message,
    required this.apiBaseUrl,
    required this.onTap,
    this.presentation = ChatMessagePresentation.normal,
    super.key,
  });

  final ChatMessage message;
  final String apiBaseUrl;
  final Future<void> Function()? onTap;
  final ChatMessagePresentation presentation;

  @override
  Widget build(BuildContext context) {
    final compact = presentation == ChatMessagePresentation.quote;
    final imageUrl = resolveApiUrl(message.linkImageUrl, apiBaseUrl);
    final content = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: compact ? null : 240,
        child: Row(
          children: <Widget>[
            if (imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  imageUrl,
                  width: compact ? 32 : 56,
                  height: compact ? 32 : 56,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _linkIcon(compact),
                ),
              )
            else
              _linkIcon(compact),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    message.linkTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!compact && message.linkDescription.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        message.linkDescription,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (!compact && message.linkUrl.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        message.linkUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (compact) {
      return content;
    }

    return MessageBubble(
      message: message,
      child: content,
    );
  }

  Widget _linkIcon(bool compact) => SizedBox(
    width: compact ? 32 : 56,
    height: compact ? 32 : 56,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.blueGrey.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(Icons.link, size: compact ? 18 : 28),
    ),
  );
}
