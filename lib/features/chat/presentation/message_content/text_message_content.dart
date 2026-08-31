import 'package:flutter/widgets.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../data/models/chat_message.dart';
import 'chat_message_presentation.dart';

/// Renders text messages, including the Markdown dialect supported by chat.
class TextMessageContent extends StatelessWidget {
  const TextMessageContent({
    required this.message,
    this.presentation = ChatMessagePresentation.normal,
    super.key,
  });

  /// Common content input. Every message-content component receives the full
  /// message so it can use metadata without changing its public contract.
  final ChatMessage message;
  final ChatMessagePresentation presentation;

  @override
  Widget build(BuildContext context) =>
      presentation == ChatMessagePresentation.quote
          ? Text(message.text, maxLines: 1, overflow: TextOverflow.ellipsis)
          :
          // Text belongs to the outer message timeline. Keeping it non-selectable
          // prevents a nested selection region from claiming drag gestures.
          MarkdownBody(data: message.text, selectable: false, shrinkWrap: true);
}
