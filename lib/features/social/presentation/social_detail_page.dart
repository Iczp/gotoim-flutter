import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/widgets/app_avatar.dart';
import '../../../core/network/api_exception.dart';
import '../application/social_identity_controller.dart';
import '../data/social_repository.dart';
import 'widgets/social_action_bar.dart';
import 'widgets/social_media_grid.dart';
import 'widgets/social_rich_text.dart';
import 'widgets/social_thread_reply_card.dart';

/// Tweet detail with thread replies (1:1 replica of X.com Post Detail - Screenshot 4).
class SocialDetailPage extends ConsumerStatefulWidget {
  const SocialDetailPage({
    super.key,
    required this.postId,
    this.initialPost,
    this.focusReply = false,
  });

  final String postId;
  final SocialPost? initialPost;
  final bool focusReply;

  @override
  ConsumerState<SocialDetailPage> createState() => _SocialDetailPageState();
}

class _SocialDetailPageState extends ConsumerState<SocialDetailPage> {
  late SocialPost? _post;
  bool _loading = true;
  String? _error;
  List<SocialPost> _replies = [];
  bool _repliesLoading = true;
  bool _isFollowingAuthor = false;

  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocusNode = FocusNode();
  bool _submittingReply = false;

  @override
  void initState() {
    super.initState();
    _post = widget.initialPost?.id == widget.postId ? widget.initialPost : null;
    _isFollowingAuthor = _post?.author?.isFollowing ?? false;
    _loadPostAndReplies();

    if (widget.focusReply) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _replyFocusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _replyController.dispose();
    _replyFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadPostAndReplies() async {
    setState(() {
      _loading = _post == null;
      _error = null;
    });
    final replies = _loadReplies();
    final repo = ref.read(socialRepositoryProvider);
    final actor = ref.read(socialIdentityProvider).actor;

    try {
      final post = await repo.getPost(widget.postId, actor?.id);
      if (mounted) {
        setState(() {
          _post = post;
          _isFollowingAuthor = post.author?.isFollowing ?? false;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted && (_post == null ||
          (e is ApiException && (e.statusCode == 403 || e.statusCode == 404)))) {
        setState(() {
          _post = null;
          _error = e is ApiException && (e.statusCode == 403 || e.statusCode == 404)
              ? '动态已不可用或无权查看。'
              : '无法加载动态详情，请检查网络。';
          _loading = false;
        });
      }
    }

    await replies;
  }

  Future<void> _loadReplies() async {
    setState(() => _repliesLoading = true);
    final repo = ref.read(socialRepositoryProvider);
    final actor = ref.read(socialIdentityProvider).actor;

    try {
      final page = await repo.getReplies(
        postId: widget.postId,
        viewerActorId: actor?.id,
      );
      if (mounted) {
        setState(() {
          _replies = page.items;
          _repliesLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _repliesLoading = false);
      }
    }
  }

  Future<void> _submitReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty || _submittingReply) return;

    final actor = ref.read(socialIdentityProvider).actor;
    if (actor == null) return;

    setState(() => _submittingReply = true);
    final repo = ref.read(socialRepositoryProvider);

    try {
      final newReply = await repo.createPost(
        actorId: actor.id,
        content: text,
        clientRequestId: const Uuid().v4(),
        parentId: widget.postId,
        replyToActorId: _post?.author?.id,
      );

      if (mounted) {
        _replyController.clear();
        _replyFocusNode.unfocus();
        setState(() {
          _replies = [newReply, ..._replies];
          if (_post != null) {
            _post = _post!.copyWith(replies: _post!.replies + 1);
          }
          _submittingReply = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('回复已发布')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submittingReply = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('回复发送失败，请重试')),
        );
      }
    }
  }

  String _formatFullDate(DateTime? dt) {
    if (dt == null) return '';
    final local = dt.toLocal();
    final year = '${local.year}'.substring(2);
    final hour = '${local.hour}'.padLeft(2, '0');
    final minute = '${local.minute}'.padLeft(2, '0');
    return '$year年${local.month}月${local.day}日, $hour:$minute';
  }

  String _formatNumber(int count) {
    if (count <= 0) return '0';
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
    final theme = Theme.of(context);
    final subStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.75),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('发帖', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_horiz_rounded),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? _buildSkeleton(theme)
                : _error != null && _post == null
                    ? Center(child: Text(_error!))
                    : RefreshIndicator(
                        onRefresh: _loadPostAndReplies,
                        child: ListView(
                          padding: EdgeInsets.zero,
                          children: [
                            // 1. Main Post Detailed Card
                            _buildMainPost(theme, subStyle),

                            const Divider(height: 1, thickness: 1),

                            // 2. "Related / View quotes" Subheader
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        '相关',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: theme.colorScheme.onSurface,
                                        ),
                                      ),
                                      const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                                    ],
                                  ),
                                  Text(
                                    '查看引用 >',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: subStyle?.color,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const Divider(height: 1, thickness: 0.5),

                            // 3. Thread Replies Stream
                            if (_repliesLoading)
                              _buildReplySkeleton(theme)
                            else if (_replies.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(32),
                                child: Center(
                                  child: Text(
                                    '暂无回复，发布你的第一条回复吧',
                                    style: subStyle,
                                  ),
                                ),
                              )
                            else
                              ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _replies.length,
                                itemBuilder: (context, index) {
                                  final reply = _replies[index];
                                  return SocialThreadReplyCard(
                                    reply: reply,
                                    isLast: index == _replies.length - 1,
                                    replyToAuthorName: _post?.author?.handle,
                                    onReply: () {
                                      _replyController.text = '@${reply.author?.handle} ';
                                      _replyFocusNode.requestFocus();
                                    },
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
          ),

          // 4. Fixed Bottom Reply Bar (Floating in screenshot 4)
          Container(
            padding: EdgeInsets.fromLTRB(
              12,
              8,
              12,
              MediaQuery.of(context).padding.bottom + 8,
            ),
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              border: Border(
                top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: TextField(
                      controller: _replyController,
                      focusNode: _replyFocusNode,
                      decoration: const InputDecoration(
                        hintText: '发布你的回复',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.image_outlined, color: Color(0xFF1D9BF0)),
                  onPressed: () {},
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1D9BF0),
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: _submittingReply ? null : _submitReply,
                  child: _submittingReply
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('回复', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeleton(ThemeData theme) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Row(children: [
        _skeletonBox(theme, 44, 44, radius: 22),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _skeletonBox(theme, 120, 14),
          const SizedBox(height: 8),
          _skeletonBox(theme, 80, 10),
        ]),
      ]),
      const SizedBox(height: 24),
      _skeletonBox(theme, double.infinity, 14),
      const SizedBox(height: 10),
      _skeletonBox(theme, double.infinity, 14),
      const SizedBox(height: 10),
      Align(alignment: Alignment.centerLeft, child: _skeletonBox(theme, 180, 14)),
      const SizedBox(height: 28),
      _skeletonBox(theme, double.infinity, 1),
      _buildReplySkeleton(theme),
    ],
  );

  Widget _buildReplySkeleton(ThemeData theme) => Padding(
    padding: const EdgeInsets.all(16),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _skeletonBox(theme, 36, 36, radius: 18),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _skeletonBox(theme, 110, 12),
        const SizedBox(height: 10),
        _skeletonBox(theme, double.infinity, 12),
        const SizedBox(height: 8),
        _skeletonBox(theme, 160, 12),
      ])),
    ]),
  );

  Widget _skeletonBox(ThemeData theme, double width, double height, {double radius = 4}) =>
      Container(width: width, height: height, decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(radius),
      ));

  Widget _buildMainPost(ThemeData theme, TextStyle? subStyle) {
    if (_post == null) return const SizedBox.shrink();
    final author = _post!.author;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Author Row + Follow Button
          Row(
            children: [
              AppAvatar(
                name: author?.name.isNotEmpty == true ? author!.name : 'User',
                imageUrl: author?.avatarUrl,
                radius: 22,
              ),
              const SizedBox(width: 12),
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
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
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
                      ],
                    ),
                    Text(
                      '@${author?.handle.isNotEmpty == true ? author!.handle : 'user'}',
                      style: subStyle,
                    ),
                  ],
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _isFollowingAuthor
                      ? Colors.transparent
                      : theme.colorScheme.onSurface,
                  foregroundColor: _isFollowingAuthor
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.surface,
                  side: _isFollowingAuthor
                      ? BorderSide(color: theme.dividerColor)
                      : BorderSide.none,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () {
                  setState(() => _isFollowingAuthor = !_isFollowingAuthor);
                },
                child: Text(
                  _isFollowingAuthor ? '已关注' : '关注',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
          ),

          // Full content
          if (_post!.content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: SocialRichText(
                text: _post!.content,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: 17,
                  height: 1.45,
                ),
              ),
            ),

          // Media Grid
          if (_post!.medias.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SocialMediaGrid(
                medias: _post!.medias,
                onMediaTap: (index, allMedias) {
                  context.push(
                    '/social/media-viewer',
                    extra: {
                      'post': _post!,
                      'initialIndex': index,
                      'medias': allMedias,
                    },
                  );
                },
              ),
            ),

          // Timestamp & Views (e.g. 26年10月27日, 18:31 · 3.6M 查看次数)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Text(_formatFullDate(_post!.publishedAt), style: subStyle),
                Text(' · ', style: subStyle),
                Text(
                  '${_formatNumber(_post!.views > 0 ? _post!.views : 12)} 查看次数',
                  style: subStyle?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),

          const Divider(height: 1, thickness: 0.5),

          // Engagement count summary row (489 评论 · 46 转发 · 1.4K 喜欢 · 413 书签)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Wrap(
              spacing: 16,
              children: [
                _buildCountItem(_post!.replies, '评论', theme),
                _buildCountItem(_post!.reposts, '转帖', theme),
                _buildCountItem(_post!.likes, '喜欢', theme),
                _buildCountItem(12, '书签', theme),
              ],
            ),
          ),

          const Divider(height: 1, thickness: 0.5),

          // 5-Action Bar
          SocialActionBar(
            replyCount: _post!.replies,
            repostCount: _post!.reposts,
            likeCount: _post!.likes,
            viewCount: _post!.views,
            isLiked: _post!.isLiked,
            isBookmarked: _post!.isBookmarked,
            onReply: () => _replyFocusNode.requestFocus(),
          ),
        ],
      ),
    );
  }

  Widget _buildCountItem(int count, String label, ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _formatNumber(count),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(fontSize: 13),
        ),
      ],
    );
  }
}
