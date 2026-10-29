import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/app_avatar.dart';
import '../../data/social_repository.dart';
import 'social_action_bar.dart';
import 'social_media_grid.dart';
import 'social_rich_text.dart';

/// Authentic X.com Tweet Feed Item Card.
class SocialPostCard extends StatelessWidget {
  const SocialPostCard({
    super.key,
    required this.post,
    this.onLike,
    this.onBookmark,
    this.onRepost,
    this.onShare,
    this.onTap,
  });

  final SocialPost post;
  final VoidCallback? onLike;
  final VoidCallback? onBookmark;
  final VoidCallback? onRepost;
  final VoidCallback? onShare;
  final VoidCallback? onTap;

  String _formatRelativeTime(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟';
    if (diff.inHours < 24) return '${diff.inHours}小时';
    if (diff.inDays < 7) return '${diff.inDays}天';
    return '${date.month}月${date.day}日';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final author = post.author;
    final subStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.75),
    );

    return InkWell(
      onTap:
          onTap ??
          () => context.push(
            '/social/detail/${Uri.encodeComponent(post.id)}',
            extra: post,
          ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Left Avatar
                AppAvatar(
                  name: author?.name.isNotEmpty == true ? author!.name : 'User',
                  imageUrl: author?.avatarUrl,
                  radius: 20,
                ),
                const SizedBox(width: 12),

                // 2. Right Body
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: Name, Verified, @handle, time, more button
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              author?.name.isNotEmpty == true
                                  ? author!.name
                                  : '社交用户',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (author?.isVerified == true) ...[
                            const SizedBox(width: 3),
                            const Icon(
                              Icons.verified_rounded,
                              size: 16,
                              color: Color(0xFF1D9BF0),
                            ),
                          ],
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '@${author?.handle.isNotEmpty == true ? author!.handle : 'user'}',
                              style: subStyle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (post.publishedAt != null) ...[
                            Text(' · ', style: subStyle),
                            Text(
                              _formatRelativeTime(post.publishedAt),
                              style: subStyle,
                            ),
                          ],
                          const Spacer(),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 24,
                              minHeight: 24,
                            ),
                            icon: Icon(
                              Icons.more_horiz_rounded,
                              size: 18,
                              color: subStyle?.color,
                            ),
                            onPressed: () => _showMoreSheet(context),
                          ),
                        ],
                      ),

                      // Content text with rich highlights
                      if (post.content.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 6),
                          child: SocialRichText(
                            text: post.content,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 15,
                              height: 1.35,
                            ),
                          ),
                        ),

                      // Media Grid
                      if (post.medias.isNotEmpty)
                        SocialMediaGrid(
                          medias: post.medias,
                          onMediaTap: (index, allMedias) {
                            context.push(
                              '/social/media-viewer',
                              extra: {
                                'post': post,
                                'initialIndex': index,
                                'medias': allMedias,
                              },
                            );
                          },
                        ),

                      // Bottom 5-column action bar
                      SocialActionBar(
                        replyCount: post.replies,
                        repostCount: post.reposts,
                        likeCount: post.likes,
                        viewCount: post.views,
                        isLiked: post.isLiked,
                        isBookmarked: post.isBookmarked,
                        onReply:
                            () => context.push(
                              '/social/detail/${Uri.encodeComponent(post.id)}?focusReply=true',
                              extra: post,
                            ),
                        onLike: onLike,
                        onBookmark: onBookmark,
                        onRepost: onRepost,
                        onShare: onShare,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 0.5,
            thickness: 0.5,
            color: theme.dividerColor.withValues(alpha: 0.25),
          ),
        ],
      ),
    );
  }

  void _showMoreSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder:
          (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.bookmark_outline_rounded),
                  title: const Text('收藏动态'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onBookmark?.call();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: const Text('复制文本'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('已复制内容到剪贴板')));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.share_outlined),
                  title: const Text('分享动态'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onShare?.call();
                  },
                ),
              ],
            ),
          ),
    );
  }
}
