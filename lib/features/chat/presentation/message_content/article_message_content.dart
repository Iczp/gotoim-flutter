import 'package:flutter/material.dart';

import '../../../../core/browser/app_webview_page.dart';
import '../../../../core/utils/api_url_resolver.dart';
import '../../data/models/article_message_item.dart';
import '../../data/models/chat_message.dart';
import 'chat_message_presentation.dart';
import 'message_bubble.dart';

class ArticleMessageContent extends StatelessWidget {
  const ArticleMessageContent({
    required this.message,
    this.apiBaseUrl = '',
    this.maxWidth,
    this.onArticleTap,
    this.presentation = ChatMessagePresentation.normal,
    super.key,
  });

  final ChatMessage message;
  final String apiBaseUrl;
  final double? maxWidth;
  final Future<void> Function(ArticleMessageItem item)? onArticleTap;
  final ChatMessagePresentation presentation;

  String _webUrl(String value) {
    final resolved = resolveApiUrl(value, apiBaseUrl);
    final uri = Uri.tryParse(resolved);
    return uri != null &&
            (uri.scheme == 'http' || uri.scheme == 'https') &&
            uri.host.isNotEmpty
        ? resolved
        : '';
  }

  Future<void> _open(BuildContext context, ArticleMessageItem item) async {
    final url = _webUrl(item.originalUrl);
    if (url.isEmpty) return;
    if (onArticleTap != null) {
      await onArticleTap!(item);
    } else {
      await AppWebViewPage.open(context, url: url, title: item.title);
    }
  }

  Widget _image(BuildContext context, ArticleMessageItem item, double height) {
    final url = _webUrl(item.coverImageUrl);
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.article_outlined, size: 32)),
    );
    return SizedBox(
      height: height,
      child: url.isEmpty
          ? placeholder
          : Image.network(
              url,
              fit: BoxFit.cover,
              width: double.infinity,
              cacheHeight: (height * MediaQuery.devicePixelRatioOf(context))
                  .round(),
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (message.isRollbacked) return const Text('消息已撤回');
    final items = message.articleItems;
    if (items.isEmpty) return const Text('文章内容不可用');
    final first = items.first;
    final colors = Theme.of(context).colorScheme;
    final compact = presentation == ChatMessagePresentation.quote;
    if (compact) {
      return InkWell(
        onTap: _webUrl(first.originalUrl).isEmpty
            ? null
            : () => _open(context, first),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.article_outlined, size: 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '${first.title.isEmpty ? '文章' : first.title}${items.length > 1 ? ' 等${items.length}篇' : ''}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = maxWidth ?? constraints.maxWidth;
        final width = available.isFinite ? available.clamp(0.0, 320.0) : 320.0;
        return MessageBubble(
          message: message,
          padding: EdgeInsets.zero,
          child: SizedBox(
            width: width,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InkWell(
                    key: const ValueKey('article-item-0'),
                    onTap: _webUrl(first.originalUrl).isEmpty
                        ? null
                        : () => _open(context, first),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _image(context, first, 156),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                first.title.isEmpty ? '文章' : first.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              if (items.length == 1 &&
                                  first.description.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    first.description,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              if (items.length == 1 && first.author.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    first.author,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (var index = 1; index < items.length; index++) ...[
                    const Divider(height: 1),
                    InkWell(
                      key: ValueKey('article-item-$index'),
                      onTap: _webUrl(items[index].originalUrl).isEmpty
                          ? null
                          : () => _open(context, items[index]),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                items[index].title.isEmpty
                                    ? '文章'
                                    : items[index].title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 56,
                              child: _image(context, items[index], 56),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
