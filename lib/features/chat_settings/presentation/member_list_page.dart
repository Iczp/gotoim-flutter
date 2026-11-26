import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/two_line_app_bar_title.dart';
import '../application/chat_settings_controller.dart';
import '../application/member_list_controller.dart';
import '../data/models/chat_member.dart';
import 'member_tile.dart';

class MemberListPage extends ConsumerStatefulWidget {
  const MemberListPage({
    required this.ownerId,
    required this.sessionUnitId,
    this.sessionTitle,
    this.initialTotalCount,
    this.isDialog = false,
    super.key,
  });
  final int ownerId;
  final String sessionUnitId;
  final String? sessionTitle;
  final int? initialTotalCount;
  final bool isDialog;

  @override
  ConsumerState<MemberListPage> createState() => _MemberListPageState();
}

class _MemberListPageState extends ConsumerState<MemberListPage> {
  late final MemberListController controller;
  final search = TextEditingController();
  final scrollController = ScrollController();
  bool checkingUnderflow = false;
  bool _managersOnly = false;

  @override
  void initState() {
    super.initState();
    controller = MemberListController(
      ref.read(chatSettingsRepositoryProvider),
      ownerId: widget.ownerId,
      sessionUnitId: widget.sessionUnitId,
      initialTotalCount: widget.initialTotalCount ?? 0,
    )..initialize();
  }

  @override
  void dispose() {
    controller.dispose();
    search.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fillViewport());
      final isOwner = controller.members.any(
        (m) => m.isCreator && m.chatObjectId == widget.ownerId,
      );
      final displayedMembers = <ChatMember>[
        ...controller.members.where(
          (m) => !_managersOnly || m.isCreator || m.isAdmin,
        ),
      ]..sort((a, b) {
        final ra = a.isCreator ? 0 : (a.isAdmin ? 1 : 2);
        final rb = b.isCreator ? 0 : (b.isAdmin ? 1 : 2);
        return ra.compareTo(rb);
      });
      final content = Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              child: SearchBar(
                controller: search,
                hintText: '搜索成员',
                leading: const Icon(Icons.search),
                trailing:
                    search.text.isEmpty
                        ? const <Widget>[]
                        : <Widget>[
                          IconButton(
                            onPressed: () {
                              search.clear();
                              controller.search('');
                            },
                            icon: const Icon(Icons.close),
                          ),
                        ],
                onSubmitted: controller.search,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Row(
                children: <Widget>[
                  ChoiceChip(
                    label: const Text('全部成员', style: TextStyle(fontSize: 12)),
                    selected: !_managersOnly,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _managersOnly = false),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text(
                      '群主与管理员',
                      style: TextStyle(fontSize: 12),
                    ),
                    selected: _managersOnly,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _managersOnly = true),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: controller.refresh,
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification.metrics.extentAfter < 180) {
                      controller.loadMore();
                    }
                    return false;
                  },
                  child: ListView.builder(
                    controller: scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: displayedMembers.length + 1,
                    itemBuilder: (context, index) {
                      if (index < displayedMembers.length) {
                        final item = displayedMembers[index];
                        return MemberTile(
                          member: item,
                          canManageAdmin: isOwner,
                          onToggleAdmin: _handleToggleAdmin,
                        );
                      }
                      if (controller.loading && displayedMembers.isEmpty) {
                        final skColor = Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withValues(alpha: 0.14);
                        return Column(
                          children: List<Widget>.generate(
                            8,
                            (_) => ListTile(
                              leading: Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: skColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              title: Container(
                                height: 14,
                                width: 120,
                                margin: const EdgeInsets.only(right: 120),
                                decoration: BoxDecoration(
                                  color: skColor,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              subtitle: Container(
                                height: 11,
                                width: 180,
                                margin: const EdgeInsets.only(top: 6, right: 60),
                                decoration: BoxDecoration(
                                  color: skColor,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                      if (controller.loading) {
                        return const Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (controller.error != null) {
                        return TextButton(
                          onPressed: controller.loadMore,
                          child: Text('加载失败，点击重试：${controller.error}'),
                        );
                      }
                      if (controller.hasMore) {
                        return TextButton(
                          onPressed: controller.loadMore,
                          child: const Text('加载更多成员'),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.all(20),
                        child: Center(
                          child: Text(
                            controller.members.isEmpty
                                ? '暂无成员'
                                : '共有 ${controller.totalCount} 人',
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context).hintColor,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );

      if (widget.isDialog) {
        return content;
      }

      return Scaffold(
        backgroundColor: WeChatPageStyle.scaffoldBg(context),
        appBar: AppBar(
          backgroundColor: WeChatPageStyle.appBarBg(context),
          scrolledUnderElevation: 0.5,
          title: TwoLineAppBarTitle(
            title:
                controller.totalCount > 0
                    ? '群聊成员 (${controller.totalCount})'
                    : '群聊成员',
            subtitle: widget.sessionTitle,
          ),
        ),
        body: content,
      );
    },
  );

  Future<void> _handleToggleAdmin(ChatMember member) async {
    final targetIsAdmin = !member.isAdmin;
    final actionText = targetIsAdmin ? '设为管理员' : '取消管理员';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(actionText),
        content: Text('确定要将「${member.name}」$actionText吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(chatSettingsRepositoryProvider).setAdmin(
        member.id,
        targetIsAdmin,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已将 ${member.name} $actionText')),
        );
      }
      await controller.refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e')),
        );
      }
    }
  }

  Future<void> _fillViewport() async {
    if (checkingUnderflow || controller.loading || !controller.hasMore) return;
    if (!scrollController.hasClients) return;
    if (scrollController.position.maxScrollExtent > 80) return;
    checkingUnderflow = true;
    try {
      await controller.loadMore();
    } finally {
      checkingUnderflow = false;
    }
  }
}
