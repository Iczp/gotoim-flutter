import 'package:flutter/material.dart';

/// Sending and retry affordances positioned beside an outgoing message bubble.
class ChatMessageDeliveryState extends StatelessWidget {
  const ChatMessageDeliveryState({
    required this.isMine,
    required this.state,
    this.onRetry,
    super.key,
  });

  final bool isMine;
  final String state;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (!isMine || state == 'sent' || state == 'received') {
      return const SizedBox.shrink();
    }
    if (state == 'sending') {
      return const Padding(
        padding: EdgeInsets.only(right: 6),
        child: SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (state == 'failed') {
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: IconButton(
          tooltip: '发送失败，点击重试',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: onRetry,
          icon: const Icon(Icons.error, color: Colors.red, size: 19),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
