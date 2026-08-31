import 'package:flutter/material.dart';
import '../../data/models/chat_message.dart';
import 'basic_message_card.dart';
import 'chat_message_presentation.dart';

class RedEnvelopeMessageContent extends StatelessWidget {
  const RedEnvelopeMessageContent({
    required this.message,
    required this.presentation,
    super.key,
  });
  final ChatMessage message;
  final ChatMessagePresentation presentation;
  @override
  Widget build(BuildContext context) => BasicMessageCard(
    icon: Icons.redeem_outlined,
    title: message.content['title']?.toString() ?? '红包',
    subtitle:
        '${message.content['description'] ?? message.content['text'] ?? ''}',
    presentation: presentation,
  );
}
