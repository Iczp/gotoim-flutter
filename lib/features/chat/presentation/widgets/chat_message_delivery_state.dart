import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Sending and retry affordances positioned beside an outgoing message bubble.
class ChatMessageDeliveryState extends StatelessWidget {
  const ChatMessageDeliveryState({
    required this.isMine,
    required this.state,
    this.errorMessage,
    this.onRetry,
    super.key,
  });

  final bool isMine;
  final String state;
  final String? errorMessage;
  final VoidCallback? onRetry;

  Future<void> _showFailedActions(BuildContext context) async {
    final detail =
        (errorMessage != null && errorMessage!.trim().isNotEmpty)
            ? errorMessage!.trim()
            : '发送失败，请检查网络或重试';
    await showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('发送失败'),
            content: SelectableText(detail),
            actions: <Widget>[
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: detail));
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已复制失败信息')),
                    );
                  }
                },
                child: const Text('复制错误信息'),
              ),
              if (onRetry != null)
                FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    onRetry!();
                  },
                  child: const Text('重新发送'),
                ),
            ],
          ),
    );
  }

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
          tooltip: '发送失败，点击查看原因或重试',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () => _showFailedActions(context),
          icon: const Icon(Icons.error, color: Colors.red, size: 19),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
