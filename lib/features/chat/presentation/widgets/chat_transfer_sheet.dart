import 'package:flutter/material.dart';

import '../../../call_center/application/call_center_controller.dart';
import '../../../call_center/data/models/transfer_target.dart';
import '../../../session/presentation/chat_object_avatar.dart';

/// 客服/店员会话转接半屏选择弹窗（ChatTransferSheet）
///
/// 核心职责：
/// 1. 展示当前店铺下可转接的店长或客服坐席列表；
/// 2. 提供搜索框输入关键词动态过滤转接对象；
/// 3. 点击客服弹出二次确认转接弹窗，确认后调用转接接口并关闭页面。
class ChatTransferSheet extends StatefulWidget {
  const ChatTransferSheet({required this.controller, super.key});

  /// 客服转接状态控制器
  final CallCenterController controller;

  @override
  State<ChatTransferSheet> createState() => _ChatTransferSheetState();
}


class _ChatTransferSheetState extends State<ChatTransferSheet> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _select(TransferTarget target) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('确认转接'),
            content: Text('确定将当前会话转接给“${target.name}”吗？'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('转接'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.controller.transferTo(target);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      // The controller retains the error for this sheet to render.
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      return Material(
        color: Theme.of(context).colorScheme.surface,
        child: Column(
          children: <Widget>[
            ListTile(
              title: const Text('转接给'),
              subtitle: const Text('选择同一店铺内可服务的店主或客服'),
              trailing: IconButton(
                tooltip: '关闭',
                onPressed:
                    controller.isSubmitting
                        ? null
                        : () => Navigator.pop(context, false),
                icon: const Icon(Icons.close),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _search,
                onChanged: controller.updateKeyword,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '搜索店主或客服',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            if (controller.error != null)
              MaterialBanner(
                content: Text('加载或转接失败：${controller.error}'),
                actions: <Widget>[
                  TextButton(
                    onPressed: controller.isLoading ? null : controller.refresh,
                    child: const Text('重试'),
                  ),
                ],
              ),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification.metrics.extentAfter < 100 &&
                      controller.hasMore &&
                      !controller.isLoading) {
                    controller.loadMore();
                  }
                  return false;
                },
                child:
                    controller.targets.isEmpty && controller.isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : controller.targets.isEmpty
                        ? const Center(child: Text('暂无可转接的客服'))
                        : ListView.builder(
                          itemCount:
                              controller.targets.length +
                              (controller.hasMore || controller.isLoading
                                  ? 1
                                  : 0),
                          itemBuilder: (context, index) {
                            if (index == controller.targets.length) {
                              return SizedBox(
                                height: 48,
                                child: Center(
                                  child:
                                      controller.isLoading
                                          ? const SizedBox.square(
                                            dimension: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                          : const Text('上拉加载更多'),
                                ),
                              );
                            }
                            final target = controller.targets[index];
                            final subtitle = <String>[
                              target.roleLabel,
                              if (target.serviceStatusDescription.isNotEmpty)
                                target.serviceStatusDescription,
                            ].join(' · ');
                            return ListTile(
                              enabled: !controller.isSubmitting,
                              leading: ChatObjectAvatar(
                                name: target.name,
                                imageUrl:
                                    target.avatarUrl.isEmpty
                                        ? null
                                        : target.avatarUrl,
                                radius: 20,
                              ),
                              title: Text(target.name),
                              subtitle: Text(subtitle),
                              trailing:
                                  controller.isSubmitting
                                      ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                      : const Icon(Icons.chevron_right),
                              onTap: () => _select(target),
                            );
                          },
                        ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
