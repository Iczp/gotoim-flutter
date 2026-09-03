import 'package:flutter/material.dart';
import '../../data/models/chat_message.dart';
import 'basic_message_card.dart';
import 'chat_message_presentation.dart';

class HtmlMessageContent extends StatelessWidget {
  const HtmlMessageContent({
    required this.message,
    required this.presentation,
    super.key,
  });
  final ChatMessage message;
  final ChatMessagePresentation presentation;
  @override
  Widget build(BuildContext context) => BasicMessageCard(
    icon: Icons.code_outlined,
    title: message.content['title']?.toString() ?? 'HTML 内容',
    subtitle: '${message.content['content'] ?? message.content['text'] ?? ''}',
    presentation: presentation,
    message: message,
  );
}
