import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/adaptive_page/adaptive_page.dart';
import '../../../core/ui/adaptive_page/adaptive_page_config.dart';
import '../../../core/ui/adaptive_page/adaptive_page_controller.dart';
import '../../../core/ui/adaptive_page/adaptive_page_presentation.dart';
import '../../chat_settings/data/models/chat_member.dart';
import '../../contact/data/models/contact_group.dart';
import '../../session/data/models/chat_owner.dart';
import '../../session/data/models/session_summary.dart';
import '../../session/data/models/session_summary_helpers.dart';
import '../../session/presentation/chat_object_avatar.dart';

enum ProfileKind { user, friend, group, member }

@immutable
class ProfileSubject {
  const ProfileSubject({
    required this.kind,
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.raw,
    this.subtitle = '',
    this.editableAvatar = false,
  });

  factory ProfileSubject.member(ChatMember member) => ProfileSubject(
    kind: ProfileKind.member,
    id: member.id,
    name: member.name,
    avatarUrl: member.avatarUrl,
    subtitle: member.isCreator ? '群主' : '会话成员',
    raw: member.raw,
  );

  factory ProfileSubject.contact(ContactEntry contact) => ProfileSubject(
    kind: contact.objectType == 2 ? ProfileKind.group : ProfileKind.friend,
    id: contact.id,
    name: contact.displayName,
    avatarUrl: contact.avatarUrl,
    subtitle: contact.objectType == 2 ? '群聊' : '好友',
    raw: contact.raw,
  );

  factory ProfileSubject.session(SessionSummary session) => ProfileSubject(
    kind: session.ownerObjectType == 2 ? ProfileKind.group : ProfileKind.friend,
    id: session.id,
    name: session.title,
    avatarUrl: _sessionAvatar(session.raw),
    subtitle: session.ownerObjectType == 2 ? '群聊资料' : '好友资料',
    raw: session.raw,
  );

  factory ProfileSubject.owner(ChatOwner owner) => ProfileSubject(
    kind: ProfileKind.user,
    id: '${owner.id}',
    name: owner.name,
    avatarUrl: owner.imageUrl ?? '',
    subtitle: owner.typeDescription,
    raw: <String, dynamic>{
      'id': owner.id,
      'displayName': owner.name,
      'objectTypeDescription': owner.typeDescription,
    },
    editableAvatar: true,
  );

  final ProfileKind kind;
  final String id;
  final String name;
  final String avatarUrl;
  final String subtitle;
  final Map<String, dynamic> raw;
  final bool editableAvatar;
}

String _sessionAvatar(Map<String, dynamic> raw) {
  final destination = asMap(raw['destination']);
  final owner = asMap(raw['owner']);
  return firstNonEmpty(<Object?>[
    destination['thumbnail'],
    destination['portrait'],
    owner['thumbnail'],
    owner['portrait'],
  ]);
}

Future<void> openProfilePage(
  BuildContext context, {
  required ProfileSubject subject,
  VoidCallback? onSendMessage,
}) async {
  await AdaptivePage.open<void>(
    context,
    config: AdaptivePageConfig(
      title: _titleFor(subject.kind),
      sheetSizingMode: AdaptiveSheetSizingMode.draggable,
      initialChildSize: .68,
      minChildSize: .42,
      maxChildSize: .96,
      fullPageMinWidth: 720,
    ),
    builder:
        (context, controller) => ProfilePage(
          subject: subject,
          adaptiveController: controller,
          onSendMessage: onSendMessage,
        ),
  );
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({
    required this.subject,
    required this.adaptiveController,
    this.onSendMessage,
    super.key,
  });

  final ProfileSubject subject;
  final AdaptivePageController adaptiveController;
  final VoidCallback? onSendMessage;

  @override
  Widget build(BuildContext context) {
    final owner = asMap(subject.raw['owner']);
    final destination = asMap(subject.raw['destination']);
    final setting = asMap(subject.raw['setting']);
    final fields = <({String label, String value})>[
      (label: 'ID', value: subject.id),
      if (subject.subtitle.isNotEmpty) (label: '类型', value: subject.subtitle),
      _field(
        '账号',
        firstNonEmpty(<Object?>[owner['code'], subject.raw['code']]),
      ),
      _field(
        '备注',
        firstNonEmpty(<Object?>[
          subject.raw['rename'],
          destination['memberName'],
        ]),
      ),
      _field('群昵称', firstNonEmpty(<Object?>[setting['memberName']])),
      _field('地区', firstNonEmpty(<Object?>[owner['area'], owner['region']])),
      _field('组织', _names(subject.raw['organizationList'])),
      _field('标签', _names(subject.raw['tagList'])),
      _field(
        '简介',
        firstNonEmpty(<Object?>[
          owner['description'],
          subject.raw['description'],
        ]),
      ),
    ].where((field) => field.value.isNotEmpty).toList(growable: false);
    return SafeArea(
      top: false,
      child: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              children: <Widget>[
                Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      ChatObjectAvatar(
                        name: subject.name,
                        imageUrl:
                            subject.avatarUrl.isEmpty
                                ? null
                                : subject.avatarUrl,
                        radius: 48,
                      ),
                      if (subject.editableAvatar)
                        Positioned(
                          right: -4,
                          bottom: -4,
                          child: IconButton.filled(
                            tooltip: '修改头像',
                            onPressed: () {
                              adaptiveController.close();
                              context.push('/settings/avatar');
                            },
                            icon: const Icon(Icons.edit, size: 18),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  subject.name,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (subject.subtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      subject.subtitle,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 20),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: fields
                        .map((field) => _ProfileField(field.label, field.value))
                        .toList(growable: false),
                  ),
                ),
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
                    adaptiveController.close();
                    onSendMessage!();
                  },
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                  label: const Text('发送消息'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static ({String label, String value}) _field(String label, String value) => (
    label: label,
    value: value,
  );

  static String _names(Object? value) =>
      value is List
          ? value
              .whereType<Map>()
              .map((item) => item['name'])
              .whereType<String>()
              .join('、')
          : '';
}

class _ProfileField extends StatelessWidget {
  const _ProfileField(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    title: Text(label, style: Theme.of(context).textTheme.bodySmall),
    subtitle: SelectableText(value),
  );
}

String _titleFor(ProfileKind kind) => switch (kind) {
  ProfileKind.user => '我的资料',
  ProfileKind.friend => '好友资料',
  ProfileKind.group => '群资料',
  ProfileKind.member => '成员资料',
};
