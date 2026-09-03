import 'package:flutter/material.dart';
import '../../data/models/chat_message.dart';
import 'basic_message_card.dart';
import 'chat_message_presentation.dart';

class LocationMessageContent extends StatelessWidget {
  const LocationMessageContent({
    required this.message,
    required this.presentation,
    super.key,
  });
  final ChatMessage message;
  final ChatMessagePresentation presentation;
  @override
  Widget build(BuildContext context) => BasicMessageCard(
    icon: Icons.location_on_outlined,
    title: message.content['name']?.toString() ?? '位置',
    subtitle:
        '${message.content['address'] ?? message.content['description'] ?? ''}',
    presentation: presentation,
    message: message,
  );
}
