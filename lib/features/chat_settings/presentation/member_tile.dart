import 'package:flutter/material.dart';

import '../../session/presentation/chat_object_avatar.dart';
import '../data/models/chat_member.dart';
import 'member_profile_sheet.dart';

class MemberTile extends StatelessWidget {
  const MemberTile({
    required this.member,
    this.compact = false,
    this.canManageAdmin = false,
    this.onToggleAdmin,
    super.key,
  });
  final ChatMember member;
  final bool compact;
  final bool canManageAdmin;
  final ValueChanged<ChatMember>? onToggleAdmin;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => showMemberDetails(context, member),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  ChatObjectAvatar(
                    name: member.name,
                    imageUrl:
                        member.avatarUrl.isEmpty ? null : member.avatarUrl,
                    radius: 20,
                    chatObjectId: member.chatObjectId,
                  ),
                  if (member.isCreator)
                    const Positioned(
                      right: -3,
                      bottom: -2,
                      child: Icon(
                        Icons.workspace_premium,
                        size: 15,
                        color: Colors.amber,
                      ),
                    )
                  else if (member.isAdmin)
                    const Positioned(
                      right: -3,
                      bottom: -2,
                      child: Icon(
                        Icons.shield,
                        size: 15,
                        color: Colors.blue,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Flexible(
                child: Text(
                  member.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
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
        chatObjectId: member.chatObjectId,
      ),
      title: Row(
        children: <Widget>[
          Flexible(child: Text(member.name, overflow: TextOverflow.ellipsis)),
          if (member.isCreator) ...<Widget>[
            const SizedBox(width: 8),
            const Chip(
              label: Text('群主', style: TextStyle(fontSize: 11, color: Colors.amber)),
              visualDensity: VisualDensity.compact,
            ),
          ] else if (member.isAdmin) ...<Widget>[
            const SizedBox(width: 8),
            const Chip(
              label: Text('管理员', style: TextStyle(fontSize: 11, color: Colors.blue)),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
      subtitle: Text(
        <String>[
          '${member.lastSendTime == null ? '加入时间' : '最后发言'}：${_formatDate(date)}',
          if (member.organizationList.isNotEmpty)
            '部门：${member.organizationList.map((item) => item.name).join('、')}',
          if (member.tagList.isNotEmpty)
            '标签：${member.tagList.map((item) => item.name).join('、')}',
        ].join('\n'),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: canManageAdmin && !member.isCreator
          ? IconButton(
              icon: Icon(
                member.isAdmin ? Icons.shield : Icons.shield_outlined,
                color: member.isAdmin ? Colors.blue : null,
              ),
              tooltip: member.isAdmin ? '取消管理员' : '设为管理员',
              onPressed: () => onToggleAdmin?.call(member),
            )
          : const Icon(Icons.chevron_right),
    );
  }

  static String _formatDate(DateTime? value) =>
      value == null
          ? '-'
          : '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  static Future<void> showMemberDetails(
    BuildContext context,
    ChatMember member,
  ) => showMemberProfileSheet(context, member);
}
