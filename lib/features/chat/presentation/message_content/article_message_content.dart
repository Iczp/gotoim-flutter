import 'package:flutter/material.dart';

import '../../../../core/browser/app_webview_page.dart';
import '../../../../core/utils/api_url_resolver.dart';
import '../../data/models/article_message_item.dart';
import '../../data/models/chat_message.dart';
import 'chat_message_presentation.dart';

/// 微信公众号图文消息卡片排版组件
///
/// 遵循微信公众号标准图文排版设计（参考实际界面截图）：
/// 1. 单图文（Single Article，items 仅 1 篇，如截图1“央视新闻”）：
///    - 顶部 16:9 封面大图；
///    - 底部白色独立内容区展示标题（16sp / w500），以及可选摘要与作者。
/// 2. 多图文（Multi Articles，items 多篇，如截图2“腾讯新闻”）：
///    - 头条主图文：16:9 封面大图，标题以白色粗体（16sp / w600）浮于封面底部渐变半透明黑遮罩之上；
///    - 次条及后续图文：列表形式，左侧文章标题（15sp / w400），右侧 56x56 方形缩略图，由极细水平分割线分隔。
/// 3. 卡片容器：
///    - 纯白背景（深色模式下自适应 surfaceContainer），圆角 10dp，极细边框与微阴影，无聊天气泡小尾巴。
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

  Widget _buildCoverImage(BuildContext context, ArticleMessageItem item) {
    final url = _webUrl(item.coverImageUrl);
    final theme = Theme.of(context);
    final placeholder = ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.article_outlined,
          size: 36,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ),
    );
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: url.isEmpty
          ? placeholder
          : Image.network(
              url,
              fit: BoxFit.cover,
              width: double.infinity,
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }

  Widget _buildThumbnail(BuildContext context, ArticleMessageItem item) {
    final url = _webUrl(item.coverImageUrl);
    final theme = Theme.of(context);
    final placeholder = ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.photo_outlined,
          size: 22,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
        ),
      ),
    );
    return SizedBox(
      width: 56,
      height: 56,
      child: url.isEmpty
          ? placeholder
          : Image.network(
              url,
              fit: BoxFit.cover,
              width: 56,
              height: 56,
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
    final theme = Theme.of(context);
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

    final isSingle = items.length == 1;
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? theme.colorScheme.surfaceContainer : Colors.white;
    final dividerColor = theme.colorScheme.outlineVariant.withValues(alpha: 0.35);

    // 统一文章消息副标题/摘要样式：比主标题更淡、更小、字号与行高一致
    final subtitleStyle = (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontSize: 13,
      fontWeight: FontWeight.normal,
      height: 1.4,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = maxWidth ?? constraints.maxWidth;
        final width = available.isFinite ? available.clamp(0.0, 480.0) : 360.0;

        return Container(
          width: width,
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isSingle) ...[
                // ==================== 单图文排版 (参考截图1: 央视新闻) ====================
                InkWell(
                  key: const ValueKey('article-item-0'),
                  onTap: _webUrl(first.originalUrl).isEmpty
                      ? null
                      : () => _open(context, first),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildCoverImage(context, first),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              first.title.isEmpty ? '文章' : first.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onSurface,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                height: 1.35,
                              ),
                            ),
                            if (first.description.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  first.description,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: subtitleStyle,
                                ),
                              ),
                            if (first.author.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  first.author,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.outline,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // ==================== 多图文排版 (参考截图2: 腾讯新闻) ====================
                // 首条主图文：标题浮于封面大图底部渐变遮罩之上
                InkWell(
                  key: const ValueKey('article-item-0'),
                  onTap: _webUrl(first.originalUrl).isEmpty
                      ? null
                      : () => _open(context, first),
                  child: Stack(
                    children: [
                      _buildCoverImage(context, first),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(14, 28, 14, 10),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Color(0xCC000000), // 80% 黑底渐变
                              ],
                            ),
                          ),
                          child: Text(
                            first.title.isEmpty ? '文章' : first.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                              shadows: [
                                Shadow(
                                  color: Colors.black54,
                                  blurRadius: 4,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // 次条及后续图文列表项：左侧标题，右侧方形缩略图
                for (var index = 1; index < items.length; index++) ...[
                  Divider(
                    height: 1,
                    thickness: 0.5,
                    indent: 14,
                    endIndent: 14,
                    color: dividerColor,
                  ),
                  InkWell(
                    key: ValueKey('article-item-$index'),
                    onTap: _webUrl(items[index].originalUrl).isEmpty
                        ? null
                        : () => _open(context, items[index]),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  items[index].title.isEmpty
                                      ? '文章'
                                      : items[index].title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: theme.colorScheme.onSurface,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    height: 1.35,
                                  ),
                                ),
                                if (items[index].description.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    items[index].description,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: subtitleStyle,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (items[index].coverImageUrl.isNotEmpty) ...[
                            const SizedBox(width: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: _buildThumbnail(context, items[index]),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

