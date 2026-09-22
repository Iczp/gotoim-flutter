import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/widgets/chat_bubble.dart';
import '../../data/models/chat_message.dart';

/// Reusable chat bubble wrapper for individual message types.
///
/// Automatically determines bubble direction ([ChatBubbleSide.right] for self,
/// [ChatBubbleSide.left] for peers) and theme colors based on [ChatMessage.isMine].
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    required this.message,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
    this.tail = const ChatBubbleTail(),
    this.style,
    this.constraints,
    this.onTap,
    this.onLongPress,
    this.onDoubleTap,
    super.key,
  });

  final ChatMessage message;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final ChatBubbleTail tail;
  final ChatBubbleStyle? style;
  final BoxConstraints? constraints;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.appTokens;
    final bubbleStyle =
        style ??
        ChatBubbleStyle.content(
          side: message.isMine ? ChatBubbleSide.right : ChatBubbleSide.left,
          backgroundColor: (message.isMine
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest)
              .withValues(alpha: tokens.chatBubbleOpacity),
          tail: tail,
          padding: padding,
        );

    return ChatBubble(
      style: bubbleStyle,
      constraints: constraints,
      onTap: onTap,
      onLongPress: onLongPress,
      onDoubleTap: onDoubleTap,
      child: child,
    );
  }
}
