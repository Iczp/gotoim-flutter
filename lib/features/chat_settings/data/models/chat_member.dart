import 'dart:convert';

import '../../../session/data/models/session_summary_helpers.dart';

class ChatMember {
  const ChatMember({
    required this.id,
    required this.score,
    required this.name,
    required this.avatarUrl,
    required this.isCreator,
    required this.joinTime,
    required this.lastSendTime,
    required this.raw,
  });

  factory ChatMember.fromJson(Map<String, dynamic> json) {
    final owner = asMap(json['owner']);
    final setting = asMap(json['setting']);
    final id = json['id']?.toString() ?? '';
    return ChatMember(
      id: id,
      score: asInt(json['score']) ?? 0,
      name: firstNonEmpty(<Object?>[
        owner['displayName'],
        json['memberName'],
        owner['name'],
        '-',
      ]),
      avatarUrl: firstNonEmpty(<Object?>[
        owner['thumbnail'],
        owner['portrait'],
      ]),
      isCreator:
          setting['isCreator'] == true || asInt(setting['isCreator']) == 1,
      joinTime: asDate(json['creationTime']),
      lastSendTime: asDate(setting['lastSendTime']),
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
  final String avatarUrl;
  final bool isCreator;
  final DateTime? joinTime;
  final DateTime? lastSendTime;
  final Map<String, dynamic> raw;

  Map<String, Object?> toDatabaseValues(
    int ownerId,
    String sessionUnitId,
  ) => <String, Object?>{
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
    'raw': jsonEncode(raw),
  };
}
