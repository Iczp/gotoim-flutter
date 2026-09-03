import 'package:flutter/material.dart';
import '../../data/models/chat_message.dart';
import 'basic_message_card.dart';
import 'chat_message_presentation.dart';

class UnsupportedMessageContent extends StatelessWidget {
  const UnsupportedMessageContent({
    required this.message,
    required this.presentation,
    super.key,
  });
  final ChatMessage message;
  final ChatMessagePresentation presentation;
  @override
  Widget build(BuildContext context) => BasicMessageCard(
    icon: Icons.warning_amber_outlined,
    title: '暂不支持的消息（类型 ${message.messageType}）',
    subtitle: message.text.isEmpty ? '请在支持该消息类型的客户端查看' : message.text,
    presentation: presentation,
    message: message,
  );
}
