import 'dart:convert';

import '../../../session/data/models/session_summary_helpers.dart';

class MemberIdName {
  const MemberIdName({required this.id, required this.name});

  factory MemberIdName.fromJson(Map<String, dynamic> json) => MemberIdName(
    id: json['id']?.toString() ?? '',
    name: firstNonEmpty(<Object?>[json['name'], json['displayName'], '-']),
  );

  final String id;
  final String name;
}

class ChatMember {
  const ChatMember({
    required this.id,
    required this.score,
    required this.name,
    this.memberName,
    required this.avatarUrl,
    required this.isCreator,
    this.isAdmin = false,
    required this.joinTime,
    required this.lastSendTime,
    required this.organizationList,
    required this.tagList,
    required this.roleList,
    required this.raw,
  });

  factory ChatMember.fromJson(Map<String, dynamic> json) {
    final owner = asMap(json['owner']);
    final setting = asMap(json['setting']);
    final id = json['id']?.toString() ?? '';
    final resolvedMemberName = firstNonEmpty(<Object?>[
      setting['memberName'],
      json['memberName'],
    ]);
    final isCreator =
        setting['isCreator'] == true || asInt(setting['isCreator']) == 1;
    final isAdmin =
        setting['isAdmin'] == true ||
        asInt(setting['isAdmin']) == 1 ||
        json['isAdmin'] == true ||
        asInt(json['isAdmin']) == 1;
    final joinTime = asDate(json['creationTime'] ?? json['joinTime']);
    final rawScore = asInt(json['score']);
    final score = rawScore ??
        ((isCreator ? 3 : (isAdmin ? 2 : 1)) * 10000000000000 -
            (joinTime?.millisecondsSinceEpoch ?? 0));

    return ChatMember(
      id: id,
      score: score,
      name: firstNonEmpty(<Object?>[
        setting['memberName'],
        json['memberName'],
        owner['displayName'],
        owner['name'],
        '-',
      ]),
      memberName: resolvedMemberName.isNotEmpty ? resolvedMemberName : null,
      avatarUrl: firstNonEmpty(<Object?>[
        owner['thumbnail'],
        owner['portrait'],
      ]),
      isCreator: isCreator,
      isAdmin: isAdmin,
      joinTime: joinTime,
      lastSendTime: asDate(setting['lastSendTime']),
      organizationList: _idNameList(json['organizationList']),
      tagList: _idNameList(json['tagList']),
      roleList: _idNameList(json['roleList']),
      raw: Map<String, dynamic>.unmodifiable(json),
    );
  }

  factory ChatMember.fromDatabaseRow(Map<String, Object?> row) =>
      ChatMember.fromJson(
        jsonDecode(row['raw'] as String) as Map<String, dynamic>,
      );

  final String id;
  final int score;
  final String name;
  final String? memberName;
  final String avatarUrl;
  final bool isCreator;
  final bool isAdmin;
  final DateTime? joinTime;
  final DateTime? lastSendTime;
  final List<MemberIdName> organizationList;
  final List<MemberIdName> tagList;
  final List<MemberIdName> roleList;
  final Map<String, dynamic> raw;

  int? get chatObjectId =>
      asInt(asMap(raw['owner'])['id']) ?? asInt(raw['ownerId']);

  ChatMember copyWith({
    bool? isAdmin,
    bool? isCreator,
    int? score,
    String? name,
    String? memberName,
    String? avatarUrl,
  }) {
    final updatedRaw = Map<String, dynamic>.from(raw);
    final updatedSetting = Map<String, dynamic>.from(asMap(raw['setting']));
    if (isAdmin != null) {
      updatedSetting['isAdmin'] = isAdmin;
      updatedRaw['isAdmin'] = isAdmin;
    }
    if (isCreator != null) {
      updatedSetting['isCreator'] = isCreator;
      updatedRaw['isCreator'] = isCreator;
    }
    if (score != null) {
      updatedRaw['score'] = score;
    }
    updatedRaw['setting'] = updatedSetting;

    return ChatMember(
      id: id,
      score: score ?? this.score,
      name: name ?? this.name,
      memberName: memberName ?? this.memberName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isCreator: isCreator ?? this.isCreator,
      isAdmin: isAdmin ?? this.isAdmin,
      joinTime: joinTime,
      lastSendTime: lastSendTime,
      organizationList: organizationList,
      tagList: tagList,
      roleList: roleList,
      raw: Map<String, dynamic>.unmodifiable(updatedRaw),
    );
  }

  Map<String, Object?> toDatabaseValues(
    int ownerId,
    String sessionUnitId,
  ) {
    final rawMap = Map<String, dynamic>.from(raw);
    final settingMap = Map<String, dynamic>.from(asMap(raw['setting']));
    settingMap['isAdmin'] = isAdmin;
    settingMap['isCreator'] = isCreator;
    rawMap['setting'] = settingMap;
    rawMap['isAdmin'] = isAdmin;
    rawMap['isCreator'] = isCreator;
    rawMap['score'] = score;

    return <String, Object?>{
      'id': id,
      'ownerId': ownerId,
      'sessionUnitId': sessionUnitId,
      'memberName': name,
      'isFriendship': asMap(raw['friendship'])['isFriendship'] == true ? 1 : 0,
      'isCreator': isCreator ? 1 : 0,
      'isList': 1,
      'score': score,
      'sorting': raw['sorting'],
      'ticks': raw['ticks'],
      'joinTime': joinTime?.millisecondsSinceEpoch,
      'createTime': joinTime?.millisecondsSinceEpoch,
      'updateTime': DateTime.now().millisecondsSinceEpoch,
      'raw': jsonEncode(rawMap),
    };
  }
}

List<MemberIdName> _idNameList(Object? value) =>
    value is List
        ? value
            .whereType<Map>()
            .map((item) => MemberIdName.fromJson(item.cast<String, dynamic>()))
            .where((item) => item.id.isNotEmpty)
            .toList(growable: false)
        : const <MemberIdName>[];
