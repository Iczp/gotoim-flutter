import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_avatar.dart';
import '../application/social_feed_controller.dart';
import '../application/social_identity_controller.dart';
import '../application/social_notifications_controller.dart';
import '../data/social_repository.dart';
import 'widgets/social_post_card.dart';

export 'widgets/social_post_card.dart';

/// Authentic X.com Feed Timeline (1:1 replica of Screenshot 3).
class SocialPage extends ConsumerStatefulWidget {
  const SocialPage({super.key, this.diagnostics = false});
  final bool diagnostics;

  @override
  ConsumerState<SocialPage> createState() => _SocialPageState();
}

class _SocialPageState extends ConsumerState<SocialPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.index =
        ref.read(socialFeedControllerProvider(widget.diagnostics)).following
            ? 1
            : 0;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(socialFeedControllerProvider(widget.diagnostics));
    final currentActor = ref.watch(socialIdentityProvider).actor;
    final unread = ref.watch(
      socialNotificationsProvider.select((s) => s.unreadCount),
    );

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF1D9BF0), // Twitter Blue
        foregroundColor: Colors.white,
        shape: const CircleBorder(),
        elevation: 4,
        onPressed: () async {
          final published = await context.push<bool>('/social/publish');
          if (published == true && context.mounted) {
            await state.refresh();
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('动态发布成功')));
            }
          }
        },
        child: const Icon(Icons.add, size: 28),
      ),
      appBar: AppBar(
        leadingWidth: 56,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Center(
            child: AppAvatar(
              name:
                  currentActor?.name.isNotEmpty == true
                      ? currentActor!.name
                      : 'User',
              imageUrl: currentActor?.avatarUrl,
              radius: 16,
            ),
          ),
        ),
        title: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF1D9BF0),
          indicatorWeight: 3,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: Colors.transparent,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
          unselectedLabelStyle: const TextStyle(fontSize: 16),
          onTap: (index) {
            state.refresh(followingFeed: index == 1);
          },
          tabs: const [Tab(text: '为你推荐'), Tab(text: '正在关注')],
        ),
        actions: [
          IconButton(
            tooltip: '社交通知',
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text(unread > 99 ? '99+' : '$unread'),
              child: const Icon(Icons.notifications_outlined),
            ),
            onPressed: () => context.push('/social/notifications'),
          ),
          if (widget.diagnostics)
            IconButton(
              tooltip: '复制诊断结果',
              icon: const Icon(Icons.copy),
              onPressed:
                  () => Clipboard.setData(
                    ClipboardData(
                      text: jsonEncode({
                        'actorId': state.actor?.id,
                        'following': state.following,
                        'itemCount': state.items.length,
                        'unreadCount': unread,
                        'elapsedMs': state.elapsedMs,
                        'error': state.error,
                      }),
                    ),
                  ),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 680,
          ), // X.com Desktop/Tablet optimal feed width
          child: RefreshIndicator(
            color: const Color(0xFF1D9BF0),
            onRefresh: () => state.refresh(),
            child:
                state.items.isEmpty && state.loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount:
                          state.items.length +
                          1 +
                          (state.showingPreviousFeed ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (state.showingPreviousFeed && index == 0) {
                          return const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text(
                              '新列表暂未加载，先显示之前的动态',
                              textAlign: TextAlign.center,
                            ),
                          );
                        }
                        final postIndex =
                            index - (state.showingPreviousFeed ? 1 : 0);
                        if (postIndex < state.items.length) {
                          final post = state.items[postIndex];
                          return SocialPostCard(
                            post: post,
                            onLike: () async {
                              final actor = state.actor;
                              if (actor == null) return;
                              final repo = ref.read(socialRepositoryProvider);
                              if (post.isLiked) {
                                await repo.unlikePost(actor.id, post.id);
                              } else {
                                await repo.likePost(actor.id, post.id);
                              }
                            },
                            onBookmark: () async {
                              final actor = state.actor;
                              if (actor == null) return;
                              final repo = ref.read(socialRepositoryProvider);
                              if (post.isBookmarked) {
                                await repo.unbookmarkPost(actor.id, post.id);
                              } else {
                                await repo.bookmarkPost(actor.id, post.id);
                              }
                            },
                          );
                        }

                        // Bottom loader or completion text
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 24,
                            horizontal: 16,
                          ),
                          child: Column(
                            children: [
                              if (state.loading)
                                const Center(child: CircularProgressIndicator())
                              else if (state.error != null) ...[
                                Text(state.error!, textAlign: TextAlign.center),
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed:
                                      state.retrySeconds > 0
                                          ? null
                                          : state.retry,
                                  child: Text(
                                    state.retrySeconds > 0
                                        ? '${state.retrySeconds} 秒后可重试'
                                        : '重试',
                                  ),
                                ),
                              ] else if (state.hasMore)
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    shape: const StadiumBorder(),
                                  ),
                                  onPressed: state.loadMore,
                                  child: Text(
                                    state.isPartial ? '继续加载' : '加载更多',
                                  ),
                                )
                              else
                                Text(
                                  state.items.isEmpty
                                      ? (state.following
                                          ? '暂无关注动态，关注更多社交用户后再来看看。'
                                          : '暂时没有推荐动态。')
                                      : '已显示全部动态',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        );
                      },
                    ),
          ),
        ),
      ),
    );
  }
}
