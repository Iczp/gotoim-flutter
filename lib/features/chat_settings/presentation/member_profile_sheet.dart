import 'package:flutter/material.dart';

import '../../../core/widgets/half_page_sheet.dart';
import '../../session/data/models/session_summary_helpers.dart';
import '../../session/presentation/chat_object_avatar.dart';
import '../data/models/chat_member.dart';

Future<void> showMemberProfileSheet(
  BuildContext context,
  ChatMember member, {
  VoidCallback? onSendMessage,
}) => showHalfPageSheet<void>(
  context: context,
  builder:
      (sheetContext) =>
          MemberProfileSheet(member: member, onSendMessage: onSendMessage),
);

class MemberProfileSheet extends StatelessWidget {
  const MemberProfileSheet({
    required this.member,
    this.onSendMessage,
    super.key,
  });

  final ChatMember member;
  final VoidCallback? onSendMessage;

  @override
  Widget build(BuildContext context) {
    final owner = asMap(member.raw['owner']);
    final setting = asMap(member.raw['setting']);
    final code = firstNonEmpty(<Object?>[owner['code'], member.raw['code']]);
    final type = firstNonEmpty(<Object?>[
      owner['objectTypeDescription'],
      owner['typeDescription'],
      member.raw['ownerTypeDescription'],
    ]);
    final memberName = firstNonEmpty(<Object?>[setting['memberName']]);
    final area = firstNonEmpty(<Object?>[owner['area'], owner['region']]);
    final description = firstNonEmpty(<Object?>[
      owner['description'],
      member.raw['description'],
    ]);

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      ChatObjectAvatar(
                        name: member.name,
                        imageUrl:
                            member.avatarUrl.isEmpty ? null : member.avatarUrl,
                        radius: 34,
                      ),
                      if (member.isCreator)
                        const Positioned(
                          right: -3,
                          bottom: -3,
                          child: Icon(
                            Icons.workspace_premium,
                            size: 20,
                            color: Colors.amber,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          member.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          member.isCreator ? '群主' : '会话成员',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (member.id.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 3),
                          Text(
                            'ID：${member.id}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (code.isNotEmpty) _ProfileField(label: '账号', value: code),
              if (type.isNotEmpty) _ProfileField(label: '类型', value: type),
              if (memberName.isNotEmpty)
                _ProfileField(label: '群昵称', value: memberName),
              if (area.isNotEmpty) _ProfileField(label: '地区', value: area),
              if (member.joinTime != null)
                _ProfileField(
                  label: '加入时间',
                  value: _formatDateTime(member.joinTime!),
                ),
              if (member.lastSendTime != null)
                _ProfileField(
                  label: '最后发言',
                  value: _formatDateTime(member.lastSendTime!),
                ),
              if (description.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ],
          ),
        ),
        if (onSendMessage != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  onSendMessage!();
                },
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: const Text('发送消息'),
              ),
            ),
          ),
      ],
    );
  }

  static String _formatDateTime(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

class _ProfileField extends StatelessWidget {
  const _ProfileField({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ),
        Expanded(child: SelectableText(value)),
      ],
    ),
  );
}
