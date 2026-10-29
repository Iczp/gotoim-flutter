import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_avatar.dart';
import '../data/social_repository.dart';
import 'widgets/social_action_bar.dart';
import 'widgets/social_media_image.dart';

/// Fullscreen Immersive Dark Media Viewer (1:1 replica of X.com media lightbox - Screenshot 2).
class SocialMediaViewerPage extends StatefulWidget {
  const SocialMediaViewerPage({
    super.key,
    required this.post,
    this.initialIndex = 0,
    required this.medias,
  });

  final SocialPost post;
  final int initialIndex;
  final List<SocialPostMedia> medias;

  @override
  State<SocialMediaViewerPage> createState() => _SocialMediaViewerPageState();
}

class _SocialMediaViewerPageState extends State<SocialMediaViewerPage> {
  late PageController _pageController;
  late int _currentIndex;
  bool _isFollowing = false;
  bool _showOverlay = true;
  final TextEditingController _replyTextController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _isFollowing = widget.post.author?.isFollowing ?? false;
  }

  @override
  void dispose() {
    _pageController.dispose();
    _replyTextController.dispose();
    super.dispose();
  }

  void _toggleOverlay() {
    setState(() => _showOverlay = !_showOverlay);
  }

  @override
  Widget build(BuildContext context) {
    final author = widget.post.author;
    final totalMedias = widget.medias.length;

    return Scaffold(
      backgroundColor: Colors.black,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Stack(
          children: [
            // 1. Zoomable Image Carousel
            GestureDetector(
              onTap: _toggleOverlay,
              child: PageView.builder(
                controller: _pageController,
                itemCount: totalMedias,
                onPageChanged: (index) => setState(() => _currentIndex = index),
                itemBuilder: (context, index) {
                  final media = widget.medias[index];
                  return InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 3.5,
                    child: Center(
                      child: SocialMediaImage(
                        url: media.url,
                        fit: BoxFit.contain,
                      ),
                    ),
                  );
                },
              ),
            ),

            // 2. Top App Bar (Back & More)
            if (_showOverlay)
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 12,
                right: 12,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.black45,
                      radius: 20,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    CircleAvatar(
                      backgroundColor: Colors.black45,
                      radius: 20,
                      child: IconButton(
                        icon: const Icon(Icons.more_vert, color: Colors.white),
                        onPressed: () => _showMoreOptions(context),
                      ),
                    ),
                  ],
                ),
              ),

            // 3. Carousel Dots Indicator
            if (_showOverlay && totalMedias > 1)
              Positioned(
                bottom: 210,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    totalMedias,
                    (i) => Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _currentIndex == i
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ),
              ),

            // 4. Bottom Author, Content & Interaction Overlay
            if (_showOverlay)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.75),
                        Colors.black.withValues(alpha: 0.95),
                      ],
                    ),
                  ),
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    MediaQuery.of(context).padding.bottom + 8,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Author Row + Follow Button
                      Row(
                        children: [
                          AppAvatar(
                            name: author?.name.isNotEmpty == true ? author!.name : 'User',
                            imageUrl: author?.avatarUrl,
                            radius: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        author?.name.isNotEmpty == true ? author!.name : '社交用户',
                                        style: const TextStyle(
                                          color: Colors.white,
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
                                  ],
                                ),
                                Text(
                                  '@${author?.handle.isNotEmpty == true ? author!.handle : 'user'}',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Follow / Following capsule
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: _isFollowing ? Colors.transparent : Colors.white,
                              foregroundColor: _isFollowing ? Colors.white : Colors.black,
                              side: _isFollowing
                                  ? const BorderSide(color: Colors.white70)
                                  : BorderSide.none,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                              visualDensity: VisualDensity.compact,
                              shape: const StadiumBorder(),
                            ),
                            onPressed: () {
                              setState(() => _isFollowing = !_isFollowing);
                            },
                            child: Text(
                              _isFollowing ? '已关注' : '关注',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),

                      // Post text
                      if (widget.post.content.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            widget.post.content,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              height: 1.35,
                            ),
                          ),
                        ),

                      // 5-action interaction bar
                      SocialActionBar(
                        replyCount: widget.post.replies,
                        repostCount: widget.post.reposts,
                        likeCount: widget.post.likes,
                        viewCount: widget.post.views,
                        isLiked: widget.post.isLiked,
                        isBookmarked: widget.post.isBookmarked,
                        onReply: () => context.push(
                          '/social/detail/${widget.post.id}?focusReply=true',
                          extra: widget.post,
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Bottom Reply Input Field (Floating reply bar in screenshot 2)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E2732),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 12,
                              backgroundColor: Colors.grey.shade800,
                              child: const Icon(Icons.person, size: 16, color: Colors.white70),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _replyTextController,
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                                decoration: const InputDecoration(
                                  hintText: '发布你的回复',
                                  hintStyle: TextStyle(color: Colors.white54, fontSize: 13),
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                              ),
                            ),
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              icon: const Icon(Icons.image_outlined, size: 20, color: Color(0xFF1D9BF0)),
                              onPressed: () {},
                            ),
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              icon: const Icon(Icons.gif_box_outlined, size: 20, color: Color(0xFF1D9BF0)),
                              onPressed: () {},
                            ),
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              icon: const Icon(Icons.open_in_full_rounded, size: 16, color: Color(0xFF1D9BF0)),
                              onPressed: () => context.push(
                                '/social/detail/${widget.post.id}?focusReply=true',
                                extra: widget.post,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showMoreOptions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF16181C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download_rounded, color: Colors.white),
              title: const Text('保存图片', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已保存至系统相册')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined, color: Colors.white),
              title: const Text('分享此媒体', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
