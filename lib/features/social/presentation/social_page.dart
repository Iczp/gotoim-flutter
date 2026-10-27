import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_avatar.dart';
import '../application/social_feed_controller.dart';
import '../application/social_notifications_controller.dart';
import '../data/social_repository.dart';

class SocialPage extends ConsumerWidget {
  const SocialPage({super.key, this.diagnostics = false});
  final bool diagnostics;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(socialFeedControllerProvider(diagnostics));
    final unread = ref.watch(
      socialNotificationsProvider.select((state) => state.unreadCount),
    );
    final notificationError =
        diagnostics
            ? ref.watch(
              socialNotificationsProvider.select((state) => state.unreadError),
            )
            : null;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.edit_outlined),
        label: const Text('发布动态'),
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
      ),
      appBar: AppBar(
        title: Text(diagnostics ? 'Social 接口诊断' : 'Social 社交'),
        actions: [
          IconButton(
            tooltip: '社交通知',
            onPressed: () => context.push('/social/notifications'),
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text(unread > 99 ? '99+' : '$unread'),
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
          if (diagnostics)
            IconButton(
              tooltip: '复制诊断结果',
              icon: const Icon(Icons.copy),
              onPressed:
                  () => Clipboard.setData(
                    ClipboardData(
                      text: jsonEncode({
                        'actorId': state.actor?.id,
                        'following': state.following,
                        'pageSize': state.pageSize,
                        'itemCount': state.items.length,
                        'unreadCount': unread,
                        'notificationError': notificationError,
                        'hasMore': state.hasMore,
                        'isPartial': state.isPartial,
                        'elapsedMs': state.elapsedMs,
                        'error': state.error,
                      }),
                    ),
                  ),
            ),
          IconButton(
            tooltip: '刷新动态',
            onPressed: state.loading ? null : () => state.refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            children: [
              if (diagnostics)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      const Text(
                        '复用当前用户与 Social audience。首次获取社交身份可能初始化 Actor。\nAndroid/iOS/平板/Windows/macOS/Linux/Web：Flutter 页面可用，需能访问 API 网关。',
                      ),
                      DropdownButtonFormField<int>(
                        initialValue: state.pageSize,
                        decoration: const InputDecoration(labelText: '每页数量'),
                        items:
                            [10, 20, 50]
                                .map(
                                  (n) => DropdownMenuItem(
                                    value: n,
                                    child: Text('$n'),
                                  ),
                                )
                                .toList(),
                        onChanged:
                            state.loading
                                ? null
                                : (value) {
                                  if (value != null) {
                                    state.pageSize = value;
                                    state.refresh();
                                  }
                                },
                      ),
                      Text(
                        '${state.loading
                            ? '执行中'
                            : state.error != null
                            ? '失败'
                            : state.elapsedMs == null
                            ? '未执行'
                            : '成功'} · ${state.elapsedMs ?? 0} ms · ${state.items.length} 条',
                      ),
                      Text('通知未读 $unread · 前台每 30 秒检查，后台暂停'),
                      if (notificationError != null) Text(notificationError),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('为你推荐'),
                      icon: Icon(Icons.auto_awesome_outlined),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('正在关注'),
                      icon: Icon(Icons.people_outline),
                    ),
                  ],
                  selected: {state.following},
                  onSelectionChanged:
                      (selection) =>
                          state.refresh(followingFeed: selection.single),
                ),
              ),
              if (state.actor != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${state.actor!.name}  @${state.actor!.handle}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => state.refresh(),
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    itemCount: state.items.length + 1,
                    itemBuilder: (context, index) {
                      if (index < state.items.length) {
                        return SocialPostCard(post: state.items[index]);
                      }
                      return Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            if (state.loading)
                              const Center(child: CircularProgressIndicator())
                            else if (state.error != null) ...[
                              Text(state.error!, textAlign: TextAlign.center),
                              TextButton(
                                onPressed: state.retry,
                                child: const Text('重试'),
                              ),
                            ] else if (state.hasMore)
                              OutlinedButton(
                                onPressed: state.loadMore,
                                child: Text(
                                  state.isPartial ? '继续查找动态' : '加载更多',
                                ),
                              )
                            else
                              Text(
                                state.items.isEmpty
                                    ? (state.following
                                        ? '暂无关注动态，关注其他社交身份后再来看看。'
                                        : '暂时没有推荐动态。')
                                    : '已显示全部动态',
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SocialPostCard extends StatelessWidget {
  const SocialPostCard({super.key, required this.post});
  final SocialPost post;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppAvatar(
                name: post.author?.name ?? '社交用户',
                imageUrl: post.author?.avatarUrl,
                radius: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.author?.name ?? '社交用户',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      '@${post.author?.handle ?? ''}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (post.content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: SelectableText(post.content),
            ),
          if (post.mediaCount > 0)
            Text(
              '包含 ${post.mediaCount} 个媒体附件',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            children: [
              Text('赞 ${post.likes}'),
              Text('回复 ${post.replies}'),
              if (post.publishedAt != null)
                Text(post.publishedAt!.toLocal().toString().split('.').first),
            ],
          ),
        ],
      ),
    ),
  );
}
