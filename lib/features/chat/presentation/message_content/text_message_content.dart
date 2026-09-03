import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../../core/native/native.dart';
import '../../../../core/widgets/app_modal.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../data/models/chat_message.dart';
import 'chat_message_presentation.dart';

/// Renders text messages, including the Markdown dialect supported by chat,
/// clickable auto-linked URLs, clickable phone numbers, and @mention highlights.
class TextMessageContent extends StatelessWidget {
  const TextMessageContent({
    required this.message,
    this.presentation = ChatMessagePresentation.normal,
    super.key,
  });

  final ChatMessage message;
  final ChatMessagePresentation presentation;

  static final _urlRegex = RegExp(
    r'(?<!\]\()(https?:\/\/[^\s\)\>]+)',
    caseSensitive: false,
  );
  static final _phoneRegex = RegExp(
    r'(?<![\d\w])(1[3-9]\d{9})(?![\d\w])',
  );
  static final _mentionRegex = RegExp(
    r'(?<!\w)@([^\s@#]+)',
  );

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
      final confirmed = await showConfirmModal(
        context: context,
        title: '访问外部网页',
        message: '即将访问：\n$link\n\n是否复制该网址？',
        confirmText: '复制网址',
      );
      if (confirmed && context.mounted) {
        await Clipboard.setData(ClipboardData(text: link));
        showToast('链接已复制到剪贴板', type: ToastType.success);
      }
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
    return MarkdownBody(
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
  }
}
