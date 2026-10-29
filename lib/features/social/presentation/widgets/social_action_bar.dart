import 'package:flutter/material.dart';

/// Authentic X.com 5-column interaction bar (Reply, Repost, Like, Views, Bookmark/Share)
class SocialActionBar extends StatefulWidget {
  const SocialActionBar({
    super.key,
    required this.replyCount,
    required this.repostCount,
    required this.likeCount,
    required this.viewCount,
    this.isLiked = false,
    this.isBookmarked = false,
    this.onReply,
    this.onRepost,
    this.onLike,
    this.onBookmark,
    this.onShare,
  });

  final int replyCount;
  final int repostCount;
  final int likeCount;
  final int viewCount;
  final bool isLiked;
  final bool isBookmarked;
  final VoidCallback? onReply;
  final VoidCallback? onRepost;
  final VoidCallback? onLike;
  final VoidCallback? onBookmark;
  final VoidCallback? onShare;

  @override
  State<SocialActionBar> createState() => _SocialActionBarState();
}

class _SocialActionBarState extends State<SocialActionBar>
    with SingleTickerProviderStateMixin {
  late bool _liked;
  late int _likeCount;
  late bool _bookmarked;
  late AnimationController _likeAnimController;
  late Animation<double> _likeScaleAnim;

  @override
  void initState() {
    super.initState();
    _liked = widget.isLiked;
    _likeCount = widget.likeCount;
    _bookmarked = widget.isBookmarked;

    _likeAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _likeScaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.35), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.35, end: 1.0), weight: 50),
    ]).animate(_likeAnimController);
  }

  @override
  void didUpdateWidget(SocialActionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isLiked != widget.isLiked) {
      _liked = widget.isLiked;
    }
    if (oldWidget.likeCount != widget.likeCount) {
      _likeCount = widget.likeCount;
    }
    if (oldWidget.isBookmarked != widget.isBookmarked) {
      _bookmarked = widget.isBookmarked;
    }
  }

  @override
  void dispose() {
    _likeAnimController.dispose();
    super.dispose();
  }

  void _handleLike() {
    setState(() {
      _liked = !_liked;
      _likeCount += _liked ? 1 : -1;
      if (_liked) {
        _likeAnimController.forward(from: 0.0);
      }
    });
    widget.onLike?.call();
  }

  void _handleBookmark() {
    setState(() {
      _bookmarked = !_bookmarked;
    });
    widget.onBookmark?.call();
  }

  String _formatNumber(int count) {
    if (count <= 0) return '';
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1).replaceAll('.0', '')}M';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1).replaceAll('.0', '')}K';
    }
    return '$count';
  }

  @override
  Widget build(BuildContext context) {
    final subColor = Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 1. Reply
          _ActionItem(
            icon: Icons.chat_bubble_outline_rounded,
            countText: _formatNumber(widget.replyCount),
            color: subColor,
            activeColor: const Color(0xFF1D9BF0),
            onTap: widget.onReply,
          ),

          // 2. Repost
          _ActionItem(
            icon: Icons.repeat_rounded,
            countText: _formatNumber(widget.repostCount),
            color: subColor,
            activeColor: const Color(0xFF00BA7C),
            onTap: widget.onRepost,
          ),

          // 3. Like
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleLike,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ScaleTransition(
                  scale: _likeScaleAnim,
                  child: Icon(
                    _liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    size: 18,
                    color: _liked ? const Color(0xFFF91880) : subColor,
                  ),
                ),
                if (_likeCount > 0) ...[
                  const SizedBox(width: 5),
                  Text(
                    _formatNumber(_likeCount),
                    style: TextStyle(
                      fontSize: 12,
                      color: _liked ? const Color(0xFFF91880) : subColor,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // 4. Views
          _ActionItem(
            icon: Icons.bar_chart_rounded,
            countText: _formatNumber(widget.viewCount > 0 ? widget.viewCount : 12),
            color: subColor,
            activeColor: const Color(0xFF1D9BF0),
            onTap: null,
          ),

          // 5. Bookmark & Share
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: Icon(
                  _bookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                  size: 18,
                  color: _bookmarked ? const Color(0xFF1D9BF0) : subColor,
                ),
                onPressed: _handleBookmark,
              ),
              const SizedBox(width: 4),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: Icon(
                  Icons.share_outlined,
                  size: 18,
                  color: subColor,
                ),
                onPressed: widget.onShare,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionItem extends StatelessWidget {
  const _ActionItem({
    required this.icon,
    required this.countText,
    required this.color,
    required this.activeColor,
    this.onTap,
  });

  final IconData icon;
  final String countText;
  final Color color;
  final Color activeColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            if (countText.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                countText,
                style: TextStyle(fontSize: 12, color: color),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
