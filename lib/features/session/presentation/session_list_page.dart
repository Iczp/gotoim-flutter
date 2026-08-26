import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/session_list_controller.dart';
import '../data/models/session_summary.dart';

class SessionListPage extends ConsumerStatefulWidget {
  const SessionListPage({super.key});

  @override
  ConsumerState<SessionListPage> createState() => _SessionListPageState();
}

class _SessionListPageState extends ConsumerState<SessionListPage> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(
      () => ref.read(sessionListControllerProvider).load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(sessionListControllerProvider);
    final sessions = controller.sessions;

    return RefreshIndicator(
      onRefresh: controller.sync,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: SearchBar(
                enabled: false,
                leading: const Icon(Icons.search),
                hintText: '搜索会话（即将支持）',
                trailing: [
                  if (controller.isSyncing)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (controller.error != null)
            SliverToBoxAdapter(
              child: _SyncErrorBanner(
                onRetry: controller.sync,
                message: controller.error.toString(),
              ),
            ),
          if (sessions.isEmpty && controller.isLoading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (sessions.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptySessions(onRetry: controller.sync),
            )
          else
            SliverList.separated(
              itemCount: sessions.length,
              itemBuilder:
                  (context, index) =>
                      _SessionListTile(session: sessions[index]),
              separatorBuilder:
                  (context, index) => const Divider(height: 1, indent: 80),
            ),
        ],
      ),
    );
  }
}

class _SessionListTile extends StatelessWidget {
  const _SessionListTile({required this.session});

  final SessionSummary session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: CircleAvatar(
        child: Text(session.title.characters.first.toUpperCase()),
      ),
      title: Row(
        children: [
          if (session.isPinned) ...[
            Icon(
              Icons.push_pin_outlined,
              size: 16,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              session.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (session.updatedAt != null)
            Text(
              _formatTime(session.updatedAt!),
              style: theme.textTheme.labelSmall,
            ),
        ],
      ),
      subtitle: Text(
        session.preview.isEmpty ? '暂无消息' : session.preview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing:
          session.unreadCount > 0
              ? Badge(
                label: Text(
                  session.unreadCount > 99 ? '99+' : '${session.unreadCount}',
                ),
              )
              : null,
      onTap:
          () => ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('聊天页面正在迁移中'))),
    );
  }
}

class _EmptySessions extends StatelessWidget {
  const _EmptySessions({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.forum_outlined, size: 56),
            const SizedBox(height: 16),
            Text('暂无会话', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('下拉刷新，或检查网络连接后重试。'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('同步会话'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncErrorBanner extends StatelessWidget {
  const _SyncErrorBanner({required this.onRetry, required this.message});

  final Future<void> Function() onRetry;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.sync_problem_outlined,
            color: colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '同步失败：$message',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colorScheme.onErrorContainer),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

String _formatTime(DateTime value) {
  final now = DateTime.now();
  if (now.year == value.year &&
      now.month == value.month &&
      now.day == value.day) {
    return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }
  return '${value.month}/${value.day}';
}
