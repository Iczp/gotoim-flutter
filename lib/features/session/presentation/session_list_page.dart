import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme_tokens.dart';
import '../../../core/theme/theme_mode_controller.dart';
import '../../../core/widgets/glass_container.dart';
import '../application/session_list_controller.dart';
import '../data/models/chat_owner.dart';
import '../data/models/session_summary.dart';
import 'chat_object_avatar.dart';
import 'session_dividers.dart';
import 'session_list_item.dart';
import 'session_unit_item.dart';

class SessionListPage extends ConsumerStatefulWidget {
  const SessionListPage({required this.onOpenOwnerDrawer, super.key});

  final VoidCallback onOpenOwnerDrawer;

  @override
  ConsumerState<SessionListPage> createState() => _SessionListPageState();
}

class _SessionListPageState extends ConsumerState<SessionListPage> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _sessionKeys = <String, GlobalKey>{};
  int _handledFocusUnreadRequest = 0;

  @override
  void initState() {
    super.initState();
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
          _CurrentOwnerHeader(
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
                  if (notification.metrics.extentAfter < 240 &&
                      controller.hasMore &&
                      !controller.isLoading) {
                    controller.loadNextPage();
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
                        child: _SignalRStatusBar(
                          state: controller.connectionState,
                          onReconnect: controller.reconnectSignalR,
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: _CurrentDeviceBar(
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
                              key: _sessionKeys.putIfAbsent(
                                item.session!.id,
                                GlobalKey.new,
                              ),
                              item: item.session!,
                              onTap:
                                  () => _openChat(
                                    context,
                                    controller,
                                    item.session!,
                                  ),
                              onLongPress:
                                  () => _showSessionMenu(
                                    context,
                                    controller,
                                    item.session!,
                                  ),
                              showDivider:
                                  index + 1 < listItems.length &&
                                  listItems[index + 1].kind ==
                                      SessionListItemKind.session,
                            ),
                            SessionListItemKind.pinnedDivider =>
                              PinnedDividerItem(
                                count: item.count,
                                hasMore: item.hasMore,
                              ),
                            SessionListItemKind.timeDivider => TimeDividerItem(
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
    final target = listItems[targetIndex].session!;
    final targetContext = _sessionKeys[target.id]?.currentContext;
    if (targetContext != null) {
      await Scrollable.ensureVisible(
        targetContext,
        alignment: 0.12,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    var estimatedOffset = 0.0;
    for (var index = 0; index < targetIndex; index++) {
      estimatedOffset +=
          listItems[index].kind == SessionListItemKind.session ? 68 : 32;
    }
    final position = _scrollController.position;
    await _scrollController.animateTo(
      estimatedOffset.clamp(position.minScrollExtent, position.maxScrollExtent),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
    if (!mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final builtContext = _sessionKeys[target.id]?.currentContext;
    if (builtContext != null && builtContext.mounted) {
      await Scrollable.ensureVisible(
        builtContext,
        alignment: 0.12,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _showSessionMenu(
    BuildContext context,
    SessionListController controller,
    SessionSummary session,
  ) async {
    final action = await showModalBottomSheet<_SessionMenuAction>(
      context: context,
      showDragHandle: true,
      builder:
          (sheetContext) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ListTile(
                  leading: ChatObjectAvatar(
                    name: session.title,
                    imageUrl: null,
                    radius: 22,
                  ),
                  title: Text(
                    session.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: const Text('会话操作'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(
                    session.isPinned
                        ? Icons.push_pin_outlined
                        : Icons.push_pin_rounded,
                  ),
                  title: Text(session.isPinned ? '取消置顶' : '置顶会话'),
                  onTap:
                      () => Navigator.pop(
                        sheetContext,
                        _SessionMenuAction.topping,
                      ),
                ),
                ListTile(
                  leading: Icon(
                    session.isImmersed
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_off_outlined,
                  ),
                  title: Text(session.isImmersed ? '开启消息通知' : '关闭消息通知'),
                  onTap:
                      () => Navigator.pop(
                        sheetContext,
                        _SessionMenuAction.notification,
                      ),
                ),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('聊天设置'),
                  onTap:
                      () => Navigator.pop(
                        sheetContext,
                        _SessionMenuAction.settings,
                      ),
                ),
                ListTile(
                  leading: Icon(
                    Icons.delete_sweep_outlined,
                    color: Theme.of(sheetContext).colorScheme.error,
                  ),
                  title: Text(
                    '清空聊天记录',
                    style: TextStyle(
                      color: Theme.of(sheetContext).colorScheme.error,
                    ),
                  ),
                  onTap:
                      () =>
                          Navigator.pop(sheetContext, _SessionMenuAction.clear),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
    );
    if (action == null || !context.mounted) return;
    if (action == _SessionMenuAction.settings) {
      await context.push(
        '/chat/${Uri.encodeComponent(session.id)}/settings'
        '?ownerId=${session.ownerId ?? controller.currentOwner?.id ?? 0}',
      );
      return;
    }
    if (action == _SessionMenuAction.clear) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: const Text('清空聊天记录'),
              content: Text('确定清空“${session.title}”的全部聊天记录吗？'),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('清空'),
                ),
              ],
            ),
      );
      if (confirmed != true || !context.mounted) return;
    }
    try {
      switch (action) {
        case _SessionMenuAction.topping:
          await controller.setTopping(session, !session.isPinned);
        case _SessionMenuAction.notification:
          await controller.setImmersed(session, !session.isImmersed);
        case _SessionMenuAction.clear:
          await controller.clearMessages(session);
        case _SessionMenuAction.settings:
          break;
      }
      if (context.mounted) {
        final message = switch (action) {
          _SessionMenuAction.topping => session.isPinned ? '已取消置顶' : '已置顶',
          _SessionMenuAction.notification =>
            session.isImmersed ? '已开启消息通知' : '已关闭消息通知',
          _SessionMenuAction.clear => '聊天记录已清空',
          _SessionMenuAction.settings => '',
        };
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('操作失败：$error')));
      }
    }
  }
}

enum _SessionMenuAction { topping, notification, settings, clear }

class _CurrentOwnerHeader extends StatelessWidget {
  const _CurrentOwnerHeader({
    required this.owner,
    required this.hasMultiple,
    required this.isConnecting,
    required this.onPressed,
  });
  final ChatOwner? owner;
  final bool hasMultiple;
  final bool isConnecting;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GlassContainer(
      borderRadius: BorderRadius.zero,
      borderWidth: 0.8,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              ChatObjectAvatar(
                name: owner?.name ?? '-',
                imageUrl: owner?.imageUrl,
                radius: 18,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  owner?.name ?? 'Goto IM',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (isConnecting) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
              if (hasMultiple)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The home shell owns this drawer so every top-level tab can open it.
class ChatOwnerDrawer extends ConsumerWidget {
  const ChatOwnerDrawer({required this.controller, super.key});
  final SessionListController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final themeMode = ref.watch(themeModeProvider);

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Text(
                    '切换聊天身份',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '快速切换深浅主题',
                    icon: Icon(
                      themeMode == ThemeMode.dark
                          ? Icons.dark_mode_rounded
                          : themeMode == ThemeMode.light
                          ? Icons.light_mode_rounded
                          : Icons.brightness_auto_rounded,
                      size: 20,
                    ),
                    onPressed:
                        () =>
                            ref
                                .read(themeModeControllerProvider.notifier)
                                .toggleTheme(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            if (controller.connectionState != SessionRealtimeStatus.connected)
              _SignalRStatusBar(
                state: controller.connectionState,
                onReconnect: controller.reconnectSignalR,
              ),
            _CurrentDeviceBar(
              label: controller.currentDeviceLabel,
              deviceCount: controller.devices.length,
              isLoading: controller.isLoadingDevices,
              onPressed: () => context.push('/devices'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                children: [
                  for (final owner in controller.owners)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: ListTile(
                        leading: ChatObjectAvatar(
                          name: owner.name,
                          imageUrl: owner.imageUrl,
                          radius: 20,
                        ),
                        title: Text(
                          owner.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle:
                            owner.typeDescription.isEmpty
                                ? null
                                : Text(owner.typeDescription),
                        trailing:
                            controller.currentOwner?.id == owner.id
                                ? Icon(
                                  Icons.check_circle_rounded,
                                  color: colorScheme.primary,
                                )
                                : owner.unreadCount > 0
                                ? Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.error,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    owner.unreadCount > 99
                                        ? '99+'
                                        : '${owner.unreadCount}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                )
                                : owner.immersedCount > 0
                                ? const Badge()
                                : const Icon(Icons.chevron_right, size: 18),
                        selected: controller.currentOwner?.id == owner.id,
                        selectedTileColor: colorScheme.primaryContainer
                            .withValues(alpha: 0.3),
                        onTap: () async {
                          Navigator.pop(context);
                          await controller.selectOwner(owner);
                        },
                      ),
                    ),
                  const Divider(height: 16),
                  ListTile(
                    leading: const Icon(Icons.qr_code_scanner_rounded),
                    title: const Text('扫一扫'),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/scan-login/scan');
                    },
                  ),
                  const ListTile(
                    leading: Icon(Icons.person_add_alt_1_outlined),
                    title: Text('添加朋友'),
                    trailing: Icon(Icons.chevron_right, size: 18),
                    enabled: false,
                  ),
                  const ListTile(
                    leading: Icon(Icons.group_add_outlined),
                    title: Text('新建群聊'),
                    trailing: Icon(Icons.chevron_right, size: 18),
                    enabled: false,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('账号与设置'),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () {
                Navigator.pop(context);
                context.push('/diagnostics/auth');
              },
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Goto IM Cross-Platform',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignalRStatusBar extends StatelessWidget {
  const _SignalRStatusBar({required this.state, required this.onReconnect});
  final SessionRealtimeStatus state;
  final Future<void> Function() onReconnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final busy =
        state == SessionRealtimeStatus.connecting ||
        state == SessionRealtimeStatus.reconnecting;
    final text = switch (state) {
      SessionRealtimeStatus.connecting => 'SignalR 正在连接…',
      SessionRealtimeStatus.reconnecting => 'SignalR 正在重新连接…',
      SessionRealtimeStatus.disconnecting => 'SignalR 正在断开…',
      SessionRealtimeStatus.disconnected => 'SignalR 已断开',
      SessionRealtimeStatus.connected => '',
    };
    return Material(
      color: colorScheme.errorContainer,
      child: InkWell(
        onTap: busy ? null : onReconnect,
        child: SizedBox(
          height: 38,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  Icons.cloud_off_outlined,
                  size: 18,
                  color: colorScheme.onErrorContainer,
                ),
              const SizedBox(width: 8),
              Text(
                text,
                style: TextStyle(
                  color: colorScheme.onErrorContainer,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (!busy)
                Text(
                  '，点击重连',
                  style: TextStyle(
                    color: colorScheme.onErrorContainer,
                    fontSize: 13,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CurrentDeviceBar extends StatelessWidget {
  const _CurrentDeviceBar({
    required this.label,
    required this.deviceCount,
    required this.isLoading,
    required this.onPressed,
  });
  final String label;
  final int deviceCount;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tokens = context.appTokens;

    return GlassContainer(
      borderRadius: BorderRadius.zero,
      backgroundColor: tokens.glassSecondarySurface,
      borderWidth: 0.6,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Icon(Icons.devices_rounded, size: 20, color: colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '当前设备：${label.isEmpty ? '未知设备' : label}'
                  '${deviceCount > 1 ? ' · 多设备登录($deviceCount)' : ''}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (isLoading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
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
