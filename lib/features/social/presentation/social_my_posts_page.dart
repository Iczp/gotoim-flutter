import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/social_feed_controller.dart';
import '../application/social_identity_controller.dart';
import '../data/social_repository.dart';
import 'widgets/social_post_card.dart';

/// The backend author feed includes both posts and replies in cursor order.
class SocialMyPostsPage extends ConsumerStatefulWidget {
  const SocialMyPostsPage({super.key});
  @override
  ConsumerState<SocialMyPostsPage> createState() => _SocialMyPostsPageState();
}

class _SocialMyPostsPageState extends ConsumerState<SocialMyPostsPage> {
  final List<SocialPost> _items = [];
  String? _cursor;
  String? _actorId;
  String? _error;
  bool _loading = false;
  bool _hasMore = false;
  String? _deleting;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(_refresh);
  }

  Future<void> _refresh() async {
    if (_deleting != null) return;
    final generation = ++_generation;
    final actor = ref.read(socialIdentityProvider).actor;
    if (actor == null) return;
    setState(() {
      _actorId = actor.id;
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(socialRepositoryProvider)
          .getActorPosts(
            actorId: actor.id,
            viewerActorId: actor.id,
            pageSize: 20,
          );
      if (!mounted ||
          generation != _generation ||
          ref.read(socialIdentityProvider).actor?.id != actor.id)
        return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _cursor = page.nextCursor;
        _hasMore = page.hasMore && _cursor?.isNotEmpty == true;
      });
    } catch (_) {
      if (mounted && generation == _generation)
        setState(() => _error = '加载失败，请重试。');
    } finally {
      if (mounted && generation == _generation)
        setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore || _actorId == null || _cursor == null) return;
    final actor = _actorId!;
    final cursor = _cursor!;
    final generation = _generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(socialRepositoryProvider)
          .getActorPosts(
            actorId: actor,
            viewerActorId: actor,
            pageSize: 20,
            cursor: cursor,
          );
      if (!mounted ||
          generation != _generation ||
          ref.read(socialIdentityProvider).actor?.id != actor)
        return;
      setState(() {
        final seen = _items.map((item) => item.id).toSet();
        _items.addAll(page.items.where((item) => seen.add(item.id)));
        _cursor = page.nextCursor;
        _hasMore =
            page.hasMore && _cursor?.isNotEmpty == true && _cursor != cursor;
      });
    } catch (_) {
      if (mounted && generation == _generation)
        setState(() => _error = '加载失败，请重试。');
    } finally {
      if (mounted && generation == _generation)
        setState(() => _loading = false);
    }
  }

  Future<void> _delete(SocialPost post) async {
    final actor = _actorId;
    if (_deleting != null || actor == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(post.parentId == null ? '删除动态？' : '删除回复？'),
            content: const Text('删除后将无法恢复。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('删除'),
              ),
            ],
          ),
    );
    if (confirmed != true ||
        !mounted ||
        ref.read(socialIdentityProvider).actor?.id != actor)
      return;
    setState(() => _deleting = post.id);
    try {
      await ref.read(socialRepositoryProvider).deletePost(actor, post.id);
      if (!mounted || ref.read(socialIdentityProvider).actor?.id != actor)
        return;
      setState(() => _items.removeWhere((item) => item.id == post.id));
      ref.invalidate(socialFeedControllerProvider);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('删除失败，请重试。')));
    } finally {
      if (mounted) setState(() => _deleting = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(socialIdentityProvider.select((state) => state.actor?.id), (
      previous,
      next,
    ) {
      if (previous != next) _refresh();
    });
    return Scaffold(
      appBar: AppBar(title: const Text('我的动态与回复')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            for (final post in _items)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const SizedBox(width: 16),
                      Text(post.parentId == null ? '动态' : '回复'),
                      const Spacer(),
                      TextButton(
                        onPressed:
                            _deleting == null && !_loading ? () => _delete(post) : null,
                        child: const Text('删除'),
                      ),
                    ],
                  ),
                  SocialPostCard(post: post),
                ],
              ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Center(
                child: TextButton(
                  onPressed: _items.isEmpty ? _refresh : _loadMore,
                  child: Text(_error!),
                ),
              )
            else if (_hasMore)
              Center(
                child: TextButton(
                  onPressed: _loadMore,
                  child: const Text('加载更多'),
                ),
              )
            else if (_items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('暂无动态或回复')),
              ),
          ],
        ),
      ),
    );
  }
}
