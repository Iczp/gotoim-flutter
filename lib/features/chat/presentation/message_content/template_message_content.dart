import 'dart:io' show Process, ProcessStartMode;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../data/models/chat_message.dart';
import '../../data/models/template_message_content.dart';
import 'chat_message_presentation.dart';
import 'message_bubble.dart';

/// 自定义模板消息卡片渲染器
class TemplateMessageContent extends StatelessWidget {
  const TemplateMessageContent({
    required this.message,
    this.presentation = ChatMessagePresentation.normal,
    this.maxWidth,
    this.onLinkTap,
    super.key,
  });

  final ChatMessage message;
  final ChatMessagePresentation presentation;
  final double? maxWidth;
  final Future<void> Function()? onLinkTap;

  @override
  Widget build(BuildContext context) {
    final isQuote = presentation == ChatMessagePresentation.quote;
    final parsed = TemplateSnapshot.parse(message.raw['content']);

    if (isQuote) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Text(
              '模板',
              style: TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              parsed.fallbackText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      );
    }

    final cardWidget = Container(
      constraints: BoxConstraints(
        minWidth: 220,
        maxWidth: maxWidth ?? 340,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: !parsed.valid || parsed.snapshot == null
            ? _buildFallbackCard(context, parsed.fallbackText)
            : _buildCardContent(context, parsed.snapshot!),
      ),
    );

    return MessageBubble(
      message: message,
      padding: EdgeInsets.zero,
      child: cardWidget,
    );
  }

  Widget _buildFallbackCard(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.amber.withValues(alpha: 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, size: 16, color: Colors.amber),
              const SizedBox(width: 6),
              Text(
                '模板消息',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber.shade900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: Colors.amber.shade900.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardContent(BuildContext context, TemplateSnapshot snapshot) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (snapshot.templateName != null && snapshot.templateName!.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.05),
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '模板',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    snapshot.templateName!,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final child in snapshot.layout.children)
                _buildNode(context, child, snapshot),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNode(
    BuildContext context,
    TemplateNode node,
    TemplateSnapshot snapshot,
  ) {
    switch (node.type) {
      case 'text':
        final tNode = node as TextNode;
        final resolvedText = tNode.text ?? _resolveBind(snapshot.data, tNode.bind);
        if (resolvedText.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            resolvedText,
            style: switch (tNode.style) {
              'heading' => const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              'secondary' => TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              _ => const TextStyle(fontSize: 13),
            },
          ),
        );

      case 'field':
        final fNode = node as FieldNode;
        final val = _resolveBind(snapshot.data, fNode.bind);
        if (val.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fNode.label,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  val,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        );

      case 'badge':
        final bNode = node as BadgeNode;
        final val = bNode.text ?? _resolveBind(snapshot.data, bNode.bind);
        if (val.isEmpty) return const SizedBox.shrink();
        final (bgColor, textColor, borderColor) = switch (bNode.tone) {
          'success' => (const Color(0xFFF6FFED), const Color(0xFF52C41A), const Color(0xFFB7EB8F)),
          'warning' => (const Color(0xFFFFFBE6), const Color(0xFFFAAD14), const Color(0xFFFFE58F)),
          'danger' => (const Color(0xFFFFF2F0), const Color(0xFFFF4D4F), const Color(0xFFFFCCC7)),
          _ => (const Color(0xFFF5F5F5), const Color(0xFF595959), const Color(0xFFD9D9D9)),
        };
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor),
              ),
              child: Text(
                val,
                style: TextStyle(fontSize: 11, color: textColor, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        );

      case 'image':
        final imgNode = node as ImageNode;
        String? imageUrl;
        if (imgNode.resourceId != null && snapshot.resources != null) {
          imageUrl = snapshot.resources![imgNode.resourceId];
        } else if (imgNode.bind != null) {
          imageUrl = _resolveBind(snapshot.data, imgNode.bind);
        }
        if (!isSafeHttpUrl(imageUrl)) return const SizedBox.shrink();
        final aspect = switch (imgNode.aspectRatio) {
          'square' => 1.0,
          'portrait' => 3 / 4,
          _ => 16 / 9,
        };
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: AspectRatio(
              aspectRatio: aspect,
              child: Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: Colors.grey.shade200,
                  child: const Center(
                    child: Icon(Icons.broken_image, color: Colors.grey),
                  ),
                ),
              ),
            ),
          ),
        );

      case 'divider':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Divider(
            height: 1,
            thickness: 1,
            color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
          ),
        );

      case 'row':
        final rNode = node as RowNode;
        final spacing = _gapSize(rNode.gap);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              for (int i = 0; i < rNode.children.length; i++) ...[
                if (i > 0) SizedBox(width: spacing),
                Expanded(child: _buildNode(context, rNode.children[i], snapshot)),
              ],
            ],
          ),
        );

      case 'column':
        final cNode = node as ColumnNode;
        final spacing = _gapSize(cNode.gap);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < cNode.children.length; i++) ...[
                if (i > 0) SizedBox(height: spacing),
                _buildNode(context, cNode.children[i], snapshot),
              ],
            ],
          ),
        );

      case 'button':
        final btnNode = node as ButtonNode;
        final act = snapshot.actions.cast<TemplateAction?>().firstWhere(
              (a) => a?.id == btnNode.actionId,
              orElse: () => null,
            );
        if (act == null) return const SizedBox.shrink();
        final bindVal = _resolveBind(snapshot.data, act.bind);
        if (bindVal.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            icon: Icon(
              act.type == 'openUrl' ? Icons.open_in_browser : Icons.copy,
              size: 14,
            ),
            label: Text(btnNode.label, style: const TextStyle(fontSize: 12)),
            onPressed: () => _handleAction(context, act, bindVal),
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  double _gapSize(String? gap) => switch (gap) {
        'small' => 4.0,
        'large' => 16.0,
        _ => 8.0,
      };

  String _resolveBind(Map<String, dynamic> data, String? bind) {
    if (bind == null || bind.isEmpty) return '';
    final val = data[bind];
    return val?.toString().trim() ?? '';
  }

  Future<void> _handleAction(
    BuildContext context,
    TemplateAction action,
    String value,
  ) async {
    if (action.type == 'copyText') {
      await Clipboard.setData(ClipboardData(text: value));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已复制到剪贴板'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    if (action.type == 'openUrl') {
      if (!isSafeHttpUrl(value)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('非法链接，已阻止打开'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      final uri = Uri.parse(value);
      if (kIsWeb) {
        // Web 平台
        return;
      }

      if (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) {
        await InAppBrowser.openWithSystemBrowser(url: WebUri(uri.toString()));
        return;
      }

      if (defaultTargetPlatform == TargetPlatform.windows) {
        await Process.start(
          'explorer.exe',
          [uri.toString()],
          mode: ProcessStartMode.detached,
          runInShell: false,
        );
        return;
      }

      final command = switch (defaultTargetPlatform) {
        TargetPlatform.macOS => 'open',
        TargetPlatform.linux => 'xdg-open',
        _ => null,
      };
      if (command != null) {
        await Process.run(command, [uri.toString()], runInShell: false);
      }
    }
  }
}
