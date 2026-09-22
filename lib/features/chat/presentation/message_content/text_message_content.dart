import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../../core/browser/app_webview_page.dart';

import '../../../../core/native/native.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/widgets/app_modal.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../data/models/chat_message.dart';
import '../widgets/chat_message_delivery_state.dart';
import 'chat_message_presentation.dart';
import 'message_bubble.dart';

/// Renders text messages, including the Markdown dialect supported by chat,
/// clickable auto-linked URLs, clickable phone numbers, and @mention highlights.
class TextMessageContent extends StatelessWidget {
  const TextMessageContent({
    required this.message,
    this.presentation = ChatMessagePresentation.normal,
    this.maxWidth,
    this.onRetry,
    super.key,
  });

  final ChatMessage message;
  final ChatMessagePresentation presentation;
  final double? maxWidth;
  final VoidCallback? onRetry;

  static final _urlRegex = RegExp(
    r'(?<!\]\()(https?:\/\/[^\s\)\>]+)',
    caseSensitive: false,
  );
  static final _phoneRegex = RegExp(r'(?<![\d\w])(1[3-9]\d{9})(?![\d\w])');
  static final _mentionRegex = RegExp(r'(?<!\w)@([^\s@#]+)');

  String _formatRichText(String text) {
    if (text.isEmpty) return text;
    var result = text;
    // Replace raw URLs with Markdown links if not already inside a markdown link
    result = result.replaceAllMapped(_urlRegex, (match) {
      final url = match.group(1)!;
      return '[$url]($url)';
    });
    // Replace phone numbers with tel: links
    result = result.replaceAllMapped(_phoneRegex, (match) {
      final phone = match.group(1)!;
      return '[$phone](tel:$phone)';
    });
    // Highlight mentions with bold primary style
    result = result.replaceAllMapped(_mentionRegex, (match) {
      final mention = match.group(0)!;
      return '**$mention**';
    });
    return result;
  }

  Future<void> _handleLinkTap(BuildContext context, String link) async {
    if (link.startsWith('tel:')) {
      final phone = link.substring(4);
      final confirmed = await showConfirmModal(
        context: context,
        title: '拨打电话',
        message: '是否呼叫 $phone？',
        confirmText: '呼叫',
      );
      if (confirmed) {
        await Native.makePhoneCall(phone);
      }
      return;
    }

    if (link.startsWith('http://') || link.startsWith('https://')) {
      await AppWebViewPage.open(context, url: link);
      return;
    }

    // Default link fallback
    await Clipboard.setData(ClipboardData(text: link));
    if (context.mounted) {
      showToast('已复制：$link', type: ToastType.info);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (presentation == ChatMessagePresentation.quote) {
      return Text(message.text, maxLines: 1, overflow: TextOverflow.ellipsis);
    }

    final theme = Theme.of(context);
    final content = MarkdownBody(
      data: _formatRichText(message.text),
      selectable: false,
      shrinkWrap: true,
      onTapLink: (text, href, title) => _handleLinkTap(context, href ?? text),
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        a: TextStyle(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
        ),
      ),
    );

    final bubble = ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: 22,
        minHeight: context.appTokens.chatMessageMinHeight,
        maxWidth: maxWidth ?? double.infinity,
      ),
      child: MessageBubble(message: message, child: content),
    );

    if (message.isMine &&
        (message.state == 'sending' || message.state == 'failed')) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          ChatMessageDeliveryState(
            isMine: message.isMine,
            state: message.state,
            onRetry: onRetry,
          ),
          Flexible(child: bubble),
        ],
      );
    }

    return bubble;
  }
}
