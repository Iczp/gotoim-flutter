import 'session_summary_helpers.dart';

class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.ownerId,
    required this.score,
    required this.ticks,
    required this.title,
    required this.preview,
    required this.updatedAt,
    required this.unreadCount,
    required this.isPinned,
    required this.raw,
  });

  factory SessionSummary.fromJson(Map<String, dynamic> json) {
    final destination = asMap(json['destination']);
    final lastMessage = asMap(json['lastMessage']);
    final setting = asMap(json['setting']);
    final title = firstNonEmpty(<Object?>[
      destination['displayName'],
      destination['memberName'],
      destination['name'],
      destination['nickName'],
      json['displayName'],
    ]);
    return SessionSummary(
      id: json['id']?.toString() ?? '',
      ownerId: asInt(json['ownerId']),
      score: asInt(json['score']) ?? asInt(json['ticks']) ?? 0,
      ticks: asInt(json['ticks']) ?? 0,
      title: title.isEmpty ? '未命名会话' : title,
      preview: messageContentText(lastMessage),
      updatedAt:
          asDate(json['lastMessageTime']) ??
          asDate(lastMessage['creationTime']) ??
          asDate(json['lastModificationTime']),
      unreadCount: asInt(json['publicBadge']) ?? 0,
      isPinned:
          (asInt(json['sorting']) ?? 0) > 0 ||
          setting['isTopping'] == true ||
          setting['isTop'] == true,
      raw: Map<String, dynamic>.unmodifiable(json),
    );
  }

  factory SessionSummary.fromDatabaseRow(Map<String, Object?> row) {
    final raw = row['raw'];
    if (raw is! String) {
      throw const FormatException('Friends.raw is missing');
    }
    final decoded = decodeJsonObject(raw);
    return SessionSummary.fromJson(decoded);
  }

  final String id;
  final int? ownerId;
  final int score;
  final int ticks;
  final String title;
  final String preview;
  final DateTime? updatedAt;
  final int unreadCount;
  final bool isPinned;
  final Map<String, dynamic> raw;

  int? get lastMessageId => asInt(asMap(raw['lastMessage'])['id']);

  String get messageTypeLabel => messageContentType(asMap(raw['lastMessage']));

  Map<String, Object?> toDatabaseValues() => <String, Object?>{
    'id': id,
    'ownerId': ownerId,
    'score': score,
    'sorting': raw['sorting'],
    'ticks': raw['ticks'],
    'createTime': millis(raw['creationTime']),
    'updateTime': updatedAt?.millisecondsSinceEpoch,
    'expireTime': millis(raw['expireTime']),
    'raw': encodeJson(raw),
  };
}
