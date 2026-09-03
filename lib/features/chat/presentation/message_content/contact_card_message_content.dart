import 'package:flutter/material.dart';
import '../../data/models/chat_message.dart';
import 'basic_message_card.dart';
import 'chat_message_presentation.dart';

class ContactCardMessageContent extends StatelessWidget {
  const ContactCardMessageContent({
    required this.message,
    required this.presentation,
    super.key,
  });
  final ChatMessage message;
  final ChatMessagePresentation presentation;
  @override
  Widget build(BuildContext context) => BasicMessageCard(
    icon: Icons.account_circle_outlined,
    title:
        message.content['title']?.toString() ??
        message.content['name']?.toString() ??
        '联系人名片',
    subtitle:
        '${message.content['description'] ?? message.content['nickName'] ?? ''}',
    presentation: presentation,
    message: message,
  );
}
