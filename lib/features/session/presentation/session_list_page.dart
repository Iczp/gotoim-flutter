import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/session_list_controller.dart';
import '../data/models/session_summary.dart';
import 'current_device_bar.dart';
import 'current_owner_header.dart';

import 'session_list_item.dart';
import 'session_menu.dart';
import 'signalr_status_bar.dart';

class SessionListPage extends ConsumerStatefulWidget {
  const SessionListPage({required this.onOpenOwnerDrawer, super.key});

  final VoidCallback onOpenOwnerDrawer;

  @override
  ConsumerState<SessionListPage> createState() => _SessionListPageState();
}

class _SessionListPageState extends ConsumerState<SessionListPage>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  int _handledFocusUnreadRequest = 0;
  int _currentScrollIndex = -1;
  int? _lastOwnerId;
  List<SessionListItem> _lastListItems = const <SessionListItem>[];
  final Map<String, GlobalKey> _sessionItemKeys = <String, GlobalKey>{};

  GlobalKey _sessionItemKey(String sessionUnitId) =>
      _sessionItemKeys.putIfAbsent(
        sessionUnitId,
        () => GlobalKey(debugLabel: 'session-list-item-$sessionUnitId'),
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _handledFocusUnreadRequest =
        ref.read(sessionListControllerProvider).focusUnreadRequest;
    _scrollController.addListener(_onScrollPositionChanged);
    Future<void>.microtask(
      () => ref.read(sessionListControllerProvider).initialize(),
    );
  }

  void _onScrollPositionChanged() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    sessionScrollTrace(
      '📍 ScrollPosition | '
      'pixels=${pos.pixels.toStringAsFixed(1)} '
      'range=[${pos.minScrollExtent.toStringAsFixed(1)}, ${pos.maxScrollExtent.toStringAsFixed(1)}] '
      'extentAfter=${pos.extentAfter.toStringAsFixed(1)}',
    );
    _scheduleVisibleAiRecovery();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleVisibleAiRecovery(force: true);
    }
  }

  /// Reads the mounted Sliver children, rather than estimating item indices
  /// from scroll pixels. Headers and divider rows therefore cannot make us
  /// query non-visible sessions.
  void _scheduleVisibleAiRecovery({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final view = View.of(context);
      final viewport =
          Offset.zero & (view.physicalSize / view.devicePixelRatio);
      final visibleSessionIds = <String>[];
      for (final item in _lastListItems) {
        final session = item.session;
        if (session == null) continue;
        final render =
            _sessionItemKey(session.id).currentContext?.findRenderObject();
        if (render is! RenderBox || !render.attached) continue;
        final bounds = render.localToGlobal(Offset.zero) & render.size;
        if (bounds.overlaps(viewport)) visibleSessionIds.add(session.id);
      }
      ref
          .read(sessionListControllerProvider)
          .updateVisibleAiSessions(visibleSessionIds, force: force);
    });
  }

  @override
  void didChangeMetrics() {
    final view = View.maybeOf(context);
    if (view != null) {
      final viewInsets = view.viewInsets;
      final size = view.physicalSize / view.devicePixelRatio;
      final offset =
          _scrollController.hasClients
              ? _scrollController.offset.toStringAsFixed(1)
              : 'unattached';
      sessionScrollTrace(
        '📐 didChangeMetrics | windowSize=$size '
        'insetsBottom=${viewInsets.bottom} scrollOffset=$offset',
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScrollPositionChanged);
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
    _lastListItems = listItems;
    _sessionItemKeys.removeWhere(
      (id, _) => !listItems.any((item) => item.session?.id == id),
    );
    _scheduleVisibleAiRecovery();
    final offsetStr =
        _scrollController.hasClients
            ? _scrollController.offset.toStringAsFixed(1)
            : 'unattached';
    final maxStr =
        _scrollController.hasClients
            ? _scrollController.position.maxScrollExtent.toStringAsFixed(1)
            : 'unattached';
    sessionScrollTrace(
      '🎨 build | sessions=${controller.sessions.length} '
      'listItems=${listItems.length} focusReq=${controller.focusUnreadRequest} '
      'scrollOffset=$offsetStr maxScrollExtent=$maxStr',
    );
    if (_lastOwnerId != controller.currentOwner?.id) {
      _lastOwnerId = controller.currentOwner?.id;
      _currentScrollIndex = -1;
    }
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
            otherUnreadCount: controller.otherUnreadCount,
            otherImmersedCount: controller.otherImmersedCount,
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
                  final deltaStr =
                      notification is ScrollUpdateNotification
                          ? 'delta=${notification.scrollDelta?.toStringAsFixed(1)}'
                          : (notification is OverscrollNotification
                              ? 'overscroll=${notification.overscroll.toStringAsFixed(1)}'
                              : '');
                  final dragStr =
                      notification is ScrollUpdateNotification
                          ? 'drag=${notification.dragDetails != null}'
                          : (notification is OverscrollNotification
                              ? 'drag=${notification.dragDetails != null}'
                              : (notification is UserScrollNotification
                                  ? 'dir=${notification.direction}'
                                  : ''));
                  sessionScrollTrace(
                    '🔔 ${notification.runtimeType} | '
                    'pixels=${notification.metrics.pixels.toStringAsFixed(1)} '
                    'extentAfter=${notification.metrics.extentAfter.toStringAsFixed(1)} '
                    'maxExtent=${notification.metrics.maxScrollExtent.toStringAsFixed(1)} '
                    '$dragStr $deltaStr isPaging=$isUserPaging',
                  );
                  if (isUserPaging &&
                      notification.metrics.extentAfter < 240 &&
                      controller.hasMore &&
                      !controller.isLoading) {
                    sessionScrollTrace(
                      '⚡ Triggering loadNextPage from user scroll',
                    );
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        controller.loadNextPage();
                      }
                    });
                  }
                  return false;
                },
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    if (controller.connectionState !=
                        SessionRealtimeStatus.connected)
                      SliverToBoxAdapter(
                        child: SignalRStatusBar(
                          state: controller.connectionState,
                          onReconnect: controller.reconnectSignalR,
                          errorDescription: controller.signalRErrorDescription,
                          hubUrl: controller.signalRHubUrl,
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: CurrentDeviceBar(
                        label: controller.currentDeviceLabel,
                        deviceCount: controller.onlineDevices.length,
                        isLoading: controller.isLoadingOnlineDevices,
                        isConnected: controller.isSignalRConnected,
                        onPressed: () => context.push('/online-devices'),
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
                          return SessionListItemView(
                            key:
                                item.session == null
                                    ? null
                                    : _sessionItemKey(item.session!.id),
                            item: item,
                            onTap:
                                item.session != null
                                    ? () => _openChat(
                                      context,
                                      controller,
                                      item.session!,
                                    )
                                    : null,
                            onLongPress:
                                item.session != null
                                    ? () => SessionMenuSheet.show(
                                      context: context,
                                      controller: controller,
                                      session: item.session!,
                                    )
                                    : null,
                            showDivider:
                                index + 1 < listItems.length &&
                                listItems[index + 1].kind ==
                                    SessionListItemKind.session,
                            aiRunning:
                                item.session != null &&
                                controller.isAiRunning(item.session!.id),
                          );
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
    final targetOwnerId = session.ownerId ?? controller.currentOwner?.id ?? 0;
    final initialOffset =
        _scrollController.hasClients
            ? _scrollController.offset.toStringAsFixed(1)
            : 'none';
    final initialMax =
        _scrollController.hasClients
            ? _scrollController.position.maxScrollExtent.toStringAsFixed(1)
            : 'none';
    sessionScrollTrace(
      '🚀 _openChat START | session=${session.id} '
      'title=${session.title} offset=$initialOffset maxExtent=$initialMax',
    );
    await context.push(
      '/chat/${Uri.encodeComponent(session.id)}'
      '?ownerId=$targetOwnerId'
      '&title=${Uri.encodeQueryComponent(session.title)}',
    );
    final returnOffset =
        _scrollController.hasClients
            ? _scrollController.offset.toStringAsFixed(1)
            : 'none';
    final returnMax =
        _scrollController.hasClients
            ? _scrollController.position.maxScrollExtent.toStringAsFixed(1)
            : 'none';
    sessionScrollTrace(
      '🔙 _openChat RETURNED | session=${session.id} '
      'offset=$returnOffset maxExtent=$returnMax',
    );
    if (!mounted) return;
    await controller.reloadVisibleLocal();
    final afterReloadOffset =
        _scrollController.hasClients
            ? _scrollController.offset.toStringAsFixed(1)
            : 'none';
    final afterReloadMax =
        _scrollController.hasClients
            ? _scrollController.position.maxScrollExtent.toStringAsFixed(1)
            : 'none';
    sessionScrollTrace(
      '🏁 _openChat AFTER reloadVisibleLocal | '
      'offset=$afterReloadOffset maxExtent=$afterReloadMax',
    );
    if (mounted &&
        _scrollController.hasClients &&
        _scrollController.position.pixels >
            _scrollController.position.maxScrollExtent) {
      sessionScrollTrace(
        '⚠️ Offset out of bounds! Clamping from '
        '${_scrollController.position.pixels} to ${_scrollController.position.maxScrollExtent}',
      );
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  Future<void> _scrollToFirstUnread(
    SessionListController _,
    List<SessionListItem> listItems,
  ) async {
    if (!mounted || !_scrollController.hasClients) return;

    // 从上次位置之后找下一个有未读的 session
    final startIndex = (_currentScrollIndex + 1).clamp(0, listItems.length);
    final targetIndex = listItems.indexWhere(
      (item) =>
          item.kind == SessionListItemKind.session &&
          item.session!.unreadCount > 0,
      startIndex,
    );

    if (targetIndex < 0) {
      // 后面没有更多未读了（或全部遍历完）-> 滚动到最顶部，并重置游标以便下次重新开始
      _currentScrollIndex = -1;
      final position = _scrollController.position;
      sessionScrollTrace('🎯 _scrollToFirstUnread | reset to top');
      await _scrollController.animateTo(
        position.minScrollExtent,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    _currentScrollIndex = targetIndex;
    var estimatedOffset = 0.0;
    for (var index = 0; index < targetIndex; index++) {
      estimatedOffset +=
          listItems[index].kind == SessionListItemKind.session ? 68.0 : 32.0;
    }
    final position = _scrollController.position;
    sessionScrollTrace(
      '🎯 _scrollToFirstUnread | targetIndex=$targetIndex '
      'estimatedOffset=$estimatedOffset currentOffset=${position.pixels}',
    );
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
