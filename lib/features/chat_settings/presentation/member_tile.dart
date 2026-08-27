import 'package:flutter/material.dart';

import '../../session/presentation/chat_object_avatar.dart';
import '../data/models/chat_member.dart';

class MemberTile extends StatelessWidget {
  const MemberTile({required this.member, this.compact = false, super.key});
  final ChatMember member;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => showMemberDetails(context, member),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  ChatObjectAvatar(
                    name: member.name,
                    imageUrl:
                        member.avatarUrl.isEmpty ? null : member.avatarUrl,
                    radius: 24,
                  ),
                  if (member.isCreator)
                    const Positioned(
                      right: -3,
                      bottom: -2,
                      child: Icon(
                        Icons.workspace_premium,
                        size: 17,
                        color: Colors.amber,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 5),
              Text(member.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      );
    }
    final date = member.lastSendTime ?? member.joinTime;
    return ListTile(
      onTap: () => showMemberDetails(context, member),
      leading: ChatObjectAvatar(
        name: member.name,
        imageUrl: member.avatarUrl.isEmpty ? null : member.avatarUrl,
        radius: 23,
      ),
      title: Row(
        children: <Widget>[
          Flexible(child: Text(member.name, overflow: TextOverflow.ellipsis)),
          if (member.isCreator) ...<Widget>[
            const SizedBox(width: 8),
            const Chip(label: Text('群主'), visualDensity: VisualDensity.compact),
          ],
        ],
      ),
      subtitle: Text(
        '${member.lastSendTime == null ? '加入时间' : '最后发言'}：${_formatDate(date)}',
      ),
      trailing: const Icon(Icons.chevron_right),
    );
  }

  static String _formatDate(DateTime? value) =>
      value == null
          ? '-'
          : '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  static Future<void> showMemberDetails(
    BuildContext context,
    ChatMember member,
  ) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder:
        (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
            child: Row(
              children: <Widget>[
                ChatObjectAvatar(
                  name: member.name,
                  imageUrl: member.avatarUrl.isEmpty ? null : member.avatarUrl,
                  radius: 32,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        member.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(member.isCreator ? '群主' : '会话成员'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
  );
}
