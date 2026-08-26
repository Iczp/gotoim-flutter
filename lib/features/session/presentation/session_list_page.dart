import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/session_list_controller.dart';
import '../data/models/session_summary.dart';
import 'session_unit_item.dart';

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
    final entries = _buildEntries(sessions);

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
            SliverList.builder(
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                if (entry.title != null) {
                  return Container(
                    color: Theme.of(context).colorScheme.surfaceContainerLowest,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Text(
                      entry.title!,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  );
                }
                return Column(
                  children: [
                    SessionUnitItem(item: entry.session!),
                    if (index + 1 < entries.length &&
                        entries[index + 1].title == null)
                      const Divider(height: 1, indent: 80),
                  ],
                );
              },
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

class _SessionEntry {
  const _SessionEntry.session(this.session) : title = null;
  const _SessionEntry.divider(this.title) : session = null;

  final SessionSummary? session;
  final String? title;
}

List<_SessionEntry> _buildEntries(List<SessionSummary> sessions) {
  final ordered = List<SessionSummary>.of(sessions)..sort((a, b) {
    final pin = (b.isPinned ? 1 : 0).compareTo(a.isPinned ? 1 : 0);
    return pin != 0 ? pin : b.score.compareTo(a.score);
  });
  final entries = <_SessionEntry>[];
  String? previous;
  var hadPinned = false;
  for (final session in ordered) {
    if (session.isPinned) {
      hadPinned = true;
    } else {
      if (hadPinned) {
        entries.add(const _SessionEntry.divider('以上是置顶会话'));
        hadPinned = false;
      }
      final bucket = _timeBucket(session.updatedAt);
      if (bucket != previous) entries.add(_SessionEntry.divider(bucket));
      previous = bucket;
    }
    entries.add(_SessionEntry.session(session));
  }
  return entries;
}

String _timeBucket(DateTime? value) {
  if (value == null) return '很久以前';
  final date = DateTime(value.year, value.month, value.day);
  final days = DateTime.now().difference(date).inDays;
  if (days <= 0) return '今天';
  if (days == 1) return '昨天';
  if (days < 3) return '三天前';
  if (days < 7) return '近一周';
  if (days < 14) return '两周前';
  if (days < 30) return '一个月前';
  if (days < 60) return '两个月前';
  if (days < 90) return '三个月前';
  if (days < 180) return '半年前';
  if (days < 365) return '1年前';
  if (days < 730) return '2年前';
  if (days < 1095) return '3年前';
  if (days < 1460) return '4年前';
  return '很久以前（5年前以上）';
}
