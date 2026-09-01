import 'package:flutter/material.dart';

import '../../../chat_settings/data/models/chat_member.dart';
import '../../../session/presentation/chat_object_avatar.dart';
import '../../application/chat_controller.dart';

/// 群聊 `@` 艾特群成员半屏选择弹窗（ChatMentionBottomSheet）
///
/// 核心职责：
/// 1. 响应输入框 `@` 符号输入，弹出半屏成员选择浮层；
/// 2. 搜索框关键词实时过滤群成员；
/// 3. 支持选择勾选并将 `@成员名 ` 格式化插入/移除到输入框光标处。
class ChatMentionBottomSheet extends StatefulWidget {
  const ChatMentionBottomSheet({
    required this.controller,
    required this.input,
    super.key,
  });

  /// 聊天状态控制器
  final ChatController controller;

  /// 输入框文本控制器
  final TextEditingController input;

  @override
  State<ChatMentionBottomSheet> createState() => _ChatMentionBottomSheetState();
}


class _ChatMentionBottomSheetState extends State<ChatMentionBottomSheet> {
  late final TextEditingController _search = TextEditingController(
    text: widget.controller.mentionKeyword,
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(ChatMember member) {
    final value = widget.controller.toggleMention(widget.input.text, member);
    widget.input.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    setState(() {});
  }

  void _finish() {
    widget.controller.dismissMention();
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder:
        (context, _) => ChatMentionPanel(
          members: widget.controller.mentionMembers,
          loading: widget.controller.mentionLoading,
          hasMore: widget.controller.mentionHasMore,
          onLoadMore: widget.controller.loadMoreMentions,
          isSelected:
              (member) => widget.controller.isMemberMentioned(
                member,
                widget.input.text,
              ),
          onSelected: _toggle,
          search: _search,
          onSearchChanged: widget.controller.updateMentionKeyword,
          onComplete: _finish,
          onDismiss: () => Navigator.pop(context, false),
        ),
  );
}

/// Panel showing members list with search bar, pagination, and multi-selection checkboxes.
class ChatMentionPanel extends StatelessWidget {
  const ChatMentionPanel({
    required this.members,
    required this.loading,
    required this.hasMore,
    required this.onLoadMore,
    required this.isSelected,
    required this.onSelected,
    required this.search,
    required this.onSearchChanged,
    required this.onComplete,
    required this.onDismiss,
    super.key,
  });

  final List<ChatMember> members;
  final bool loading;
  final bool hasMore;
  final Future<void> Function() onLoadMore;
  final bool Function(ChatMember member) isSelected;
  final ValueChanged<ChatMember> onSelected;
  final TextEditingController search;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onComplete;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Material(
    elevation: 10,
    color: Theme.of(context).colorScheme.surface,
    child: SizedBox.expand(
      child: Column(
        children: <Widget>[
          ListTile(
            title: const Text('提及成员'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextButton(onPressed: onComplete, child: const Text('完成')),
                IconButton(
                  tooltip: '关闭',
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: search,
              autofocus: true,
              onChanged: onSearchChanged,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜索成员',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.metrics.extentAfter < 100 &&
                    hasMore &&
                    !loading) {
                  onLoadMore();
                }
                return false;
              },
              child:
                  members.isEmpty && loading
                      ? const SizedBox(
                        height: 72,
                        child: Center(child: CircularProgressIndicator()),
                      )
                      : members.isEmpty
                      ? const SizedBox(
                        height: 72,
                        child: Center(child: Text('未找到可提及的成员')),
                      )
                      : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount:
                            members.length + (loading || hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == members.length) {
                            return SizedBox(
                              height: 42,
                              child: Center(
                                child:
                                    loading
                                        ? const SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                        : const Text('上拉加载更多成员'),
                              ),
                            );
                          }
                          final member = members[index];
                          final selected = isSelected(member);
                          return ListTile(
                            dense: true,
                            leading: ChatObjectAvatar(
                              name: member.name,
                              imageUrl:
                                  member.avatarUrl.isEmpty
                                      ? null
                                      : member.avatarUrl,
                              radius: 17,
                            ),
                            title: Text(
                              member.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Checkbox(
                              value: selected,
                              onChanged: (_) => onSelected(member),
                            ),
                            onTap: () => onSelected(member),
                          );
                        },
                      ),
            ),
          ),
        ],
      ),
    ),
  );
}
