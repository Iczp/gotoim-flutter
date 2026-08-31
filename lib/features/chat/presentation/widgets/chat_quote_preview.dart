import 'package:flutter/material.dart';

/// Shared quote frame for the timeline and composer.
///
/// The child is always rendered by [ChatMessageContentRenderer], so a quoted
/// message uses the same attachment, audio and media interactions as its
/// original message. This widget owns only quote-specific placement and the
/// optional dismiss action.
class ChatQuotePreview extends StatelessWidget {
  const ChatQuotePreview({
    required this.senderName,
    required this.content,
    this.onTap,
    this.onClear,
    super.key,
  });

  final String senderName;
  final Widget content;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          constraints: const BoxConstraints(minHeight: 34),
          padding: EdgeInsets.only(left: 8, right: onClear == null ? 8 : 2),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(7),
            border: Border(
              left: BorderSide(color: theme.colorScheme.primary, width: 3),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Flexible(
                child: Text(
                  senderName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Expanded(child: content),
              if (onClear != null)
                IconButton(
                  tooltip: '取消引用',
                  onPressed: onClear,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 18),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
