import 'package:flutter/material.dart';

import '../../../../core/widgets/app_avatar.dart';
import '../../data/social_repository.dart';
import 'social_action_bar.dart';
import 'social_rich_text.dart';

/// Renders a reply in the conversation with X.com threaded connecting line.
class SocialThreadReplyCard extends StatelessWidget {
  const SocialThreadReplyCard({
    super.key,
    required this.reply,
    this.isLast = false,
    this.replyToAuthorName,
    this.onLike,
    this.onReply,
  });

  final SocialPost reply;
  final bool isLast;
  final String? replyToAuthorName;
  final VoidCallback? onLike;
  final VoidCallback? onReply;

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
    final author = reply.author;
    final subStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.75),
    );
    final threadLineColor = theme.dividerColor.withValues(alpha: 0.4);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Column: Avatar + Thread Connecting Line
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 12),
            child: Column(
              children: [
                AppAvatar(
                  name: author?.name.isNotEmpty == true ? author!.name : 'User',
                  imageUrl: author?.avatarUrl,
                  radius: 18,
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: threadLineColor,
                    ),
                  ),
              ],
            ),
          ),

          // Right Body
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 16, bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Author Header
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          author?.name.isNotEmpty == true ? author!.name : '社交用户',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (author?.isVerified == true) ...[
                        const SizedBox(width: 3),
                        const Icon(
                          Icons.verified_rounded,
                          size: 14,
                          color: Color(0xFF1D9BF0),
                        ),
                      ],
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '@${author?.handle.isNotEmpty == true ? author!.handle : 'user'}',
                          style: subStyle,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (reply.publishedAt != null) ...[
                        Text(' · ', style: subStyle),
                        Text(
                          _formatRelativeTime(reply.publishedAt),
                          style: subStyle,
                        ),
                      ],
                    ],
                  ),

                  // Replying to label
                  if (replyToAuthorName != null && replyToAuthorName!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 2),
                      child: Text(
                        '回复 @$replyToAuthorName',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                        ),
                      ),
                    ),

                  // Reply text content
                  if (reply.content.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 4),
                      child: SocialRichText(
                        text: reply.content,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                    ),

                  // Lightweight interaction bar
                  SocialActionBar(
                    replyCount: reply.replies,
                    repostCount: reply.reposts,
                    likeCount: reply.likes,
                    viewCount: reply.views,
                    isLiked: reply.isLiked,
                    isBookmarked: reply.isBookmarked,
                    onReply: onReply,
                    onLike: onLike,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
