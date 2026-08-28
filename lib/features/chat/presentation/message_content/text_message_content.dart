import 'package:flutter/widgets.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// Renders text messages, including the Markdown dialect supported by chat.
class TextMessageContent extends StatelessWidget {
  const TextMessageContent({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      MarkdownBody(data: text, selectable: true, shrinkWrap: true);
}
