import 'package:flutter/foundation.dart';

import '../../../chat_settings/data/models/chat_member.dart';
import '../../../contact/data/models/contact_group.dart';
import '../../../session/data/models/chat_owner.dart';
import '../../../session/data/models/session_summary.dart';
import '../../../session/data/models/session_summary_helpers.dart';

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

/// 解析资料卡结构化数据的通用 Helper
class ProfileData {
  ProfileData(ProfileSubject subject) {
    final owner = asMap(subject.raw['owner']);
    final destination = asMap(subject.raw['destination']);
    final setting = asMap(subject.raw['setting']);

    displayName = subject.name;
    originalNickname = firstNonEmpty(<Object?>[
      owner['displayName'],
      owner['name'],
      subject.raw['nickname'],
      destination['memberName'],
      setting['memberName'],
    ]);
    showNickname =
        originalNickname.isNotEmpty && originalNickname != displayName;

    accountCode = firstNonEmpty(<Object?>[
      owner['code'],
      subject.raw['code'],
      subject.id,
    ]);

    region = firstNonEmpty(<Object?>[
      owner['area'],
      owner['region'],
      subject.raw['area'],
      subject.raw['region'],
    ]);

    phone = firstNonEmpty(<Object?>[
      owner['phone'],
      owner['phoneNumber'],
      subject.raw['phone'],
      subject.raw['phoneNumber'],
    ]);

    gender = asInt(owner['gender']) ?? asInt(subject.raw['gender']) ?? 0;

    description = firstNonEmpty(<Object?>[
      owner['description'],
      subject.raw['description'],
    ]);

    chatObjectId =
        asInt(destination['id']) ??
        asInt(subject.raw['destinationId']) ??
        asInt(subject.raw['id']);

    isGroup = subject.kind == ProfileKind.group;
  }

  late final String displayName;
  late final String originalNickname;
  late final bool showNickname;
  late final String accountCode;
  late final String region;
  late final String phone;
  late final int gender; // 1: 男, 2: 女, 0: 未知
  late final String description;
  late final int? chatObjectId;
  late final bool isGroup;
}

String titleForProfileKind(ProfileKind kind) => switch (kind) {
  ProfileKind.user => '我的资料',
  ProfileKind.friend => '好友资料',
  ProfileKind.group => '群资料',
  ProfileKind.member => '成员资料',
};
