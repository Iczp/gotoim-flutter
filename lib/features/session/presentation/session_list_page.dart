import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/realtime/signalr_gateway.dart';
import '../application/session_list_controller.dart';
import '../data/models/chat_owner.dart';
import 'chat_object_avatar.dart';
import 'session_dividers.dart';
import 'session_list_item.dart';
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
      () => ref.read(sessionListControllerProvider).initialize(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(sessionListControllerProvider);
    final listItems = buildSessionListItems(
      controller.sessions,
      hasMore: controller.hasMore,
    );
    return Scaffold(
      drawer: _OwnerDrawer(controller: controller),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Builder(
              builder:
                  (context) => _CurrentOwnerHeader(
                    owner: controller.currentOwner,
                    hasMultiple: controller.owners.length > 1,
                    isConnecting: controller.isRefreshing,
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
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
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
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
                                item: item.session!,
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
                              SessionListItemKind.timeDivider =>
                                TimeDividerItem(
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
      ),
    );
  }
}

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
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLowest,
    child: InkWell(
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            ChatObjectAvatar(
              name: owner?.name ?? '-',
              imageUrl: owner?.imageUrl,
              radius: 16,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                owner?.name ?? '-',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
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
            if (hasMultiple) const Icon(Icons.keyboard_arrow_down),
          ],
        ),
      ),
    ),
  );
}

class _OwnerDrawer extends StatelessWidget {
  const _OwnerDrawer({required this.controller});
  final SessionListController controller;

  @override
  Widget build(BuildContext context) => Drawer(
    child: SafeArea(
      child: Column(
        children: [
          ListTile(
            title: const Text('切换聊天'),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          if (controller.connectionState != SignalRConnectionState.connected)
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
              children: [
                for (final owner in controller.owners)
                  ListTile(
                    leading: ChatObjectAvatar(
                      name: owner.name,
                      imageUrl: owner.imageUrl,
                      radius: 22,
                    ),
                    title: Text(owner.name),
                    subtitle:
                        owner.typeDescription.isEmpty
                            ? null
                            : Text(owner.typeDescription),
                    trailing:
                        controller.currentOwner?.id == owner.id
                            ? const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                            )
                            : owner.unreadCount > 0
                            ? Badge(
                              label: Text(
                                owner.unreadCount > 99
                                    ? '99+'
                                    : '${owner.unreadCount}',
                              ),
                            )
                            : owner.immersedCount > 0
                            ? const Badge()
                            : const Icon(Icons.arrow_forward_ios, size: 16),
                    selected: controller.currentOwner?.id == owner.id,
                    onTap: () async {
                      Navigator.pop(context);
                      await controller.selectOwner(owner);
                    },
                  ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.qr_code_scanner),
                  title: const Text('扫一扫'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/scan-login/scan');
                  },
                ),
                const ListTile(
                  leading: Icon(Icons.person_add_alt_1),
                  title: Text('添加朋友'),
                  trailing: Icon(Icons.chevron_right),
                  enabled: false,
                ),
                const ListTile(
                  leading: Icon(Icons.group_add),
                  title: Text('新建群聊'),
                  trailing: Icon(Icons.chevron_right),
                  enabled: false,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.account_circle),
            title: const Text('账号'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.pop(context);
              context.push('/diagnostics/auth');
            },
          ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Goto IM',
              style: TextStyle(color: Colors.grey, fontSize: 11),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SignalRStatusBar extends StatelessWidget {
  const _SignalRStatusBar({required this.state, required this.onReconnect});
  final SignalRConnectionState state;
  final Future<void> Function() onReconnect;

  @override
  Widget build(BuildContext context) {
    final busy =
        state == SignalRConnectionState.connecting ||
        state == SignalRConnectionState.reconnecting;
    final text = switch (state) {
      SignalRConnectionState.connecting => 'SignalR 正在连接…',
      SignalRConnectionState.reconnecting => 'SignalR 正在重新连接…',
      SignalRConnectionState.disconnecting => 'SignalR 正在断开…',
      SignalRConnectionState.disconnected => 'SignalR 已断开',
      SignalRConnectionState.connected => '',
    };
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      child: InkWell(
        onTap: busy ? null : onReconnect,
        child: SizedBox(
          height: 36,
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
                const Icon(Icons.cloud_off_outlined, size: 18),
              const SizedBox(width: 8),
              Text(text),
              if (!busy) const Text('，点击重连'),
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
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFF0F0F0),
    child: InkWell(
      onTap: onPressed,
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              const SizedBox(
                width: 48,
                child: Icon(Icons.devices_outlined, color: Colors.lightBlue),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '当前设备：${label.isEmpty ? '未知设备' : label}'
                  '${deviceCount > 1 ? ' · 多设备登录($deviceCount)' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (isLoading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: Colors.grey,
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({required this.controller});
  final SessionListController controller;
  @override
  Widget build(BuildContext context) {
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
            style: const TextStyle(color: Colors.grey),
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
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.forum_outlined, size: 56),
        const SizedBox(height: 12),
        const Text('暂无会话'),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('重新加载'),
        ),
      ],
    ),
  );
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
