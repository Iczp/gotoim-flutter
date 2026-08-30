import 'package:flutter/widgets.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../data/models/chat_message.dart';

/// Renders text messages, including the Markdown dialect supported by chat.
class TextMessageContent extends StatelessWidget {
  const TextMessageContent({required this.message, super.key});

  /// Common content input. Every message-content component receives the full
  /// message so it can use metadata without changing its public contract.
  final ChatMessage message;

  @override
  Widget build(BuildContext context) =>
  // Text belongs to the outer message timeline. Keeping it non-selectable
  // prevents a nested selection region from claiming drag gestures.
  MarkdownBody(data: message.text, selectable: false, shrinkWrap: true);
}
