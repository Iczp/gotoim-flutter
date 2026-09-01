import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/session_list_controller.dart';
import '../data/models/session_summary.dart';
import 'current_device_bar.dart';
import 'current_owner_header.dart';

import 'session_dividers.dart';
import 'session_list_item.dart';
import 'session_menu.dart';
import 'session_unit_item.dart';
import 'signalr_status_bar.dart';

class SessionListPage extends ConsumerStatefulWidget {
  const SessionListPage({required this.onOpenOwnerDrawer, super.key});

  final VoidCallback onOpenOwnerDrawer;

  @override
  ConsumerState<SessionListPage> createState() => _SessionListPageState();
}

class _SessionListPageState extends ConsumerState<SessionListPage> {
  final ScrollController _scrollController = ScrollController();
  int _handledFocusUnreadRequest = 0;

  @override
  void initState() {
    super.initState();
    _handledFocusUnreadRequest =
        ref.read(sessionListControllerProvider).focusUnreadRequest;
    Future<void>.microtask(
      () => ref.read(sessionListControllerProvider).initialize(),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(sessionListControllerProvider);
    final listItems = buildSessionListItems(
      controller.sessions,
      hasMore: controller.hasMore,
    );
    if (_handledFocusUnreadRequest != controller.focusUnreadRequest) {
      _handledFocusUnreadRequest = controller.focusUnreadRequest;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToFirstUnread(controller, listItems),
      );
    }
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          CurrentOwnerHeader(
            owner: controller.currentOwner,
            hasMultiple: controller.owners.length > 1,
            isConnecting: controller.isRefreshing,
            onPressed: widget.onOpenOwnerDrawer,
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: controller.refreshChanges,
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  final isUserPaging =
                      (notification is ScrollUpdateNotification &&
                          (notification.dragDetails != null ||
                              (notification.scrollDelta != null &&
                                  notification.scrollDelta! > 0))) ||
                      (notification is OverscrollNotification &&
                          notification.dragDetails != null);
                  if (isUserPaging &&
                      notification.metrics.extentAfter < 240 &&
                      controller.hasMore &&
                      !controller.isLoading) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        controller.loadNextPage();
                      }
                    });
                  }
                  return false;
                },
                child: CustomScrollView(
                  key: const PageStorageKey<String>(
                    'session_list_custom_scroll_view',
                  ),
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    if (controller.connectionState !=
                        SessionRealtimeStatus.connected)
                      SliverToBoxAdapter(
                        child: SignalRStatusBar(
                          state: controller.connectionState,
                          onReconnect: controller.reconnectSignalR,
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: CurrentDeviceBar(
                        label: controller.currentDeviceLabel,
                        deviceCount: controller.devices.length,
                        isLoading: controller.isLoadingDevices,
                        onPressed: () => context.push('/devices'),
                      ),
                    ),
                    if (controller.error != null)
                      SliverToBoxAdapter(
                        child: _ErrorBanner(
                          error: controller.error!,
                          onRetry: controller.loadNextPage,
                        ),
                      ),
                    if (controller.sessions.isEmpty && controller.isLoading)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (controller.sessions.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyState(onRetry: controller.loadNextPage),
                      )
                    else
                      SliverList.builder(
                        itemCount: listItems.length,
                        itemBuilder: (context, index) {
                          final item = listItems[index];
                          return switch (item.kind) {
                            SessionListItemKind.session => SessionUnitItem(
                              key: ValueKey(item.session!.id),
                              item: item.session!,
                              onTap:
                                  () => _openChat(
                                    context,
                                    controller,
                                    item.session!,
                                  ),
                              onLongPress:
                                  () => SessionMenuSheet.show(
                                    context: context,
                                    controller: controller,
                                    session: item.session!,
                                  ),
                              showDivider:
                                  index + 1 < listItems.length &&
                                  listItems[index + 1].kind ==
                                      SessionListItemKind.session,
                            ),
                            SessionListItemKind.pinnedDivider =>
                              PinnedDividerItem(
                                key: const ValueKey('pinned_divider'),
                                count: item.count,
                                hasMore: item.hasMore,
                              ),
                            SessionListItemKind.timeDivider => TimeDividerItem(
                              key: ValueKey('time_divider_${item.title}'),
                              text: item.title!,
                              count: item.count,
                              hasMore: item.hasMore,
                            ),
                          };
                        },
                      ),
                    SliverToBoxAdapter(
                      child: _LoadMoreFooter(controller: controller),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openChat(
    BuildContext context,
    SessionListController controller,
    SessionSummary session,
  ) async {
    await context.push(
      '/chat/${Uri.encodeComponent(session.id)}'
      '?ownerId=${session.ownerId ?? controller.currentOwner?.id ?? 0}'
      '&title=${Uri.encodeQueryComponent(session.title)}',
    );
    if (!mounted) return;
    await controller.reloadVisibleLocal();
  }

  Future<void> _scrollToFirstUnread(
    SessionListController _,
    List<SessionListItem> listItems,
  ) async {
    if (!mounted || !_scrollController.hasClients) return;
    final targetIndex = listItems.indexWhere(
      (item) =>
          item.kind == SessionListItemKind.session &&
          item.session!.unreadCount > 0,
    );
    if (targetIndex < 0) return;

    var estimatedOffset = 0.0;
    for (var index = 0; index < targetIndex; index++) {
      estimatedOffset +=
          listItems[index].kind == SessionListItemKind.session ? 68.0 : 32.0;
    }
    final position = _scrollController.position;
    await _scrollController.animateTo(
      estimatedOffset.clamp(position.minScrollExtent, position.maxScrollExtent),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }
}

class _LoadMoreFooter extends StatelessWidget {



  const _LoadMoreFooter({required this.controller});
  final SessionListController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (controller.isLoading && controller.sessions.isNotEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (!controller.hasMore && controller.sessions.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            '共有 ${controller.totalCount ?? controller.sessions.length} 个好友',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRetry});
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 40,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '暂无会话',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '好友和最近消息将在此处显示',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重新加载'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error, required this.onRetry});
  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => MaterialBanner(
    content: Text('加载失败：$error', maxLines: 2, overflow: TextOverflow.ellipsis),
    actions: [TextButton(onPressed: onRetry, child: const Text('重试'))],
  );
}
