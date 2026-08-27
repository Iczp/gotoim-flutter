import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../session/application/session_list_controller.dart';
import '../application/chat_settings_controller.dart';
import 'member_tile.dart';

class ChatSettingsPage extends ConsumerStatefulWidget {
  const ChatSettingsPage({
    required this.ownerId,
    required this.sessionUnitId,
    super.key,
  });
  final int ownerId;
  final String sessionUnitId;

  @override
  ConsumerState<ChatSettingsPage> createState() => _ChatSettingsPageState();
}

class _ChatSettingsPageState extends ConsumerState<ChatSettingsPage> {
  late final ChatSettingsController controller;

  @override
  void initState() {
    super.initState();
    controller = ChatSettingsController(
      ref.read(chatSettingsRepositoryProvider),
      ref.read(sessionRepositoryProvider),
      ownerId: widget.ownerId,
      sessionUnitId: widget.sessionUnitId,
    )..initialize();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder:
        (context, _) => Scaffold(
          appBar: AppBar(title: const Text('聊天设置')),
          body: RefreshIndicator(
            onRefresh: controller.refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: <Widget>[
                if (controller.error != null)
                  MaterialBanner(
                    content: Text('加载失败：${controller.error}'),
                    actions: <Widget>[
                      TextButton(
                        onPressed: controller.refresh,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                _MemberPreview(controller: controller),
                const SizedBox(height: 10),
                _section(<Widget>[
                  ListTile(
                    title: const Text('类型'),
                    trailing: Text(controller.objectTypeLabel),
                  ),
                  if (controller.objectType == 2)
                    ListTile(
                      title: const Text('群名称'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 180),
                            child: Text(
                              controller.title,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                ]),
                const SizedBox(height: 10),
                _section(<Widget>[
                  const ListTile(
                    leading: Icon(Icons.search),
                    title: Text('查找聊天记录'),
                    trailing: Icon(Icons.chevron_right),
                  ),
                ]),
                const SizedBox(height: 10),
                _section(<Widget>[
                  SwitchListTile(
                    title: const Text('免打扰'),
                    value: controller.isImmersed,
                    onChanged:
                        controller.updating ? null : controller.setImmersed,
                  ),
                  SwitchListTile(
                    title: const Text('置顶聊天'),
                    value: controller.isTopping,
                    onChanged:
                        controller.updating ? null : controller.setTopping,
                  ),
                ]),
                const SizedBox(height: 10),
                _section(<Widget>[
                  ListTile(
                    title: const Text(
                      '清空聊天记录',
                      style: TextStyle(color: Colors.red),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _confirmClear,
                  ),
                  const ListTile(
                    title: Text('投诉'),
                    trailing: Icon(Icons.chevron_right),
                  ),
                ]),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
  );

  Widget _section(List<Widget> children) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: Column(children: children),
  );

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('清空聊天记录'),
            content: const Text('将同时清除服务器和本机保存的该会话消息，确定继续吗？'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('清空'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await controller.clearMessages();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('聊天记录已清空')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('清空失败：$error')));
      }
    }
  }
}

class _MemberPreview extends StatelessWidget {
  const _MemberPreview({required this.controller});
  final ChatSettingsController controller;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        children: <Widget>[
          if (controller.loading && controller.members.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                childAspectRatio: .78,
                mainAxisSpacing: 4,
              ),
              itemCount: controller.members.length,
              itemBuilder:
                  (context, index) => MemberTile(
                    member: controller.members[index],
                    compact: true,
                  ),
            ),
          TextButton(
            onPressed:
                controller.totalCount == 0
                    ? null
                    : () => context.push(
                      '/chat/${Uri.encodeComponent(controller.sessionUnitId)}/members'
                      '?ownerId=${controller.ownerId}',
                    ),
            child: Text('查看更多（${controller.totalCount}）'),
          ),
        ],
      ),
    ),
  );
}
