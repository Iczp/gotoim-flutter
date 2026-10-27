import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../application/social_notifications_controller.dart';
import '../data/social_repository.dart';
import 'social_page.dart';

class SocialNotificationsPage extends ConsumerStatefulWidget {
  const SocialNotificationsPage({super.key});
  @override
  ConsumerState<SocialNotificationsPage> createState() =>
      _SocialNotificationsPageState();
}

class _SocialNotificationsPageState
    extends ConsumerState<SocialNotificationsPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(socialNotificationsProvider).load();
    });
  }

  Future<void> _open(SocialNotification item) async {
    final state = ref.read(socialNotificationsProvider);
    if (!item.isRead && !await state.markRead(id: item.id)) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(state.error ?? '标记已读失败')));
      }
      return;
    }
    if (!mounted || item.postId == null || state.actor == null) return;
    final request = ref
        .read(socialRepositoryProvider)
        .getPost(item.postId!, state.actor!.id);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder:
          (context) => SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .75,
              child: FutureBuilder<SocialPost>(
                future: request,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          snapshot.error is ApiException
                              ? (snapshot.error! as ApiException).message
                              : '动态不可用或无权查看。',
                        ),
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return SingleChildScrollView(
                    child: SocialPostCard(post: snapshot.data!),
                  );
                },
              ),
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(socialNotificationsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Social 通知${state.unreadCount > 0 ? ' (${state.unreadCount})' : ''}',
        ),
        actions: [
          TextButton(
            onPressed:
                state.marking || !state.hasSnapshot
                    ? null
                    : () async {
                      if (!await state.markRead() && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(state.error ?? '标记已读失败')),
                        );
                      }
                    },
            child: const Text('全部已读'),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: RefreshIndicator(
            onRefresh: state.load,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: state.items.length + 1,
              itemBuilder: (context, index) {
                if (index == state.items.length) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        if (state.error != null) ...[
                          Text(state.error!),
                          TextButton(
                            onPressed:
                                state.loading ? null : () => state.load(),
                            child: const Text('重试'),
                          ),
                        ],
                        if (state.loading)
                          const Center(child: CircularProgressIndicator())
                        else if (state.hasMore)
                          TextButton(
                            onPressed: () => state.load(more: true),
                            child: const Text('加载更多'),
                          )
                        else if (state.error == null)
                          Text(state.items.isEmpty ? '暂无社交通知' : '已显示全部通知'),
                      ],
                    ),
                  );
                }
                final item = state.items[index];
                return ListTile(
                  enabled: !state.marking,
                  leading: Badge(
                    isLabelVisible: !item.isRead,
                    child: const Icon(Icons.notifications_outlined),
                  ),
                  title: Text(
                    item.title,
                    style: TextStyle(
                      fontWeight:
                          item.isRead ? FontWeight.normal : FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    [
                      if (item.content?.isNotEmpty == true) item.content!,
                      if (item.createdAt != null)
                        item.createdAt!.toLocal().toString().split('.').first,
                    ].join('\n'),
                  ),
                  trailing:
                      item.postId != null
                          ? const Icon(Icons.chevron_right)
                          : null,
                  onTap: () => _open(item),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
