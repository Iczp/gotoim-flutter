import 'package:flutter/material.dart';
import '../../data/models/chat_message.dart';
import 'basic_message_card.dart';
import 'chat_message_presentation.dart';

class ArticleMessageContent extends StatelessWidget {
  const ArticleMessageContent({
    required this.message,
    required this.presentation,
    super.key,
  });
  final ChatMessage message;
  final ChatMessagePresentation presentation;
  @override
  Widget build(BuildContext context) => BasicMessageCard(
    icon: Icons.article_outlined,
    title: message.content['title']?.toString() ?? '文章',
    subtitle:
        '${message.content['description'] ?? message.content['summary'] ?? ''}',
    presentation: presentation,
  );
}
