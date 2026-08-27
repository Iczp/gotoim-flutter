import '../../../session/data/models/session_summary_helpers.dart';

class ChatMessage {
  const ChatMessage({
    required this.localId,
    required this.serverId,
    required this.clientMessageId,
    required this.ownerId,
    required this.sessionUnitId,
    required this.senderSessionUnitId,
    required this.messageType,
    required this.state,
    required this.score,
    required this.createdAt,
    required this.raw,
  });

  factory ChatMessage.fromJson(
    Map<String, dynamic> json, {
    required int ownerId,
    required String sessionUnitId,
  }) {
    final serverId = asInt(json['id']);
    final clientId = json['clientMessageId']?.toString();
    final sender = asMap(json['senderSessionUnit']);
    return ChatMessage(
      localId: clientId ?? 'server-$serverId',
      serverId: serverId,
      clientMessageId: clientId,
      ownerId: ownerId,
      sessionUnitId: sessionUnitId,
      senderSessionUnitId: sender['id']?.toString(),
      messageType: asInt(json['messageType']) ?? 0,
      state: 'received',
      score: (serverId ?? 0) * 1000000,
      createdAt: asDate(json['creationTime']),
      raw: Map<String, dynamic>.unmodifiable(json),
    );
  }

  factory ChatMessage.fromDatabaseRow(Map<String, Object?> row) {
    final raw = decodeJsonObject(row['raw'] as String);
    return ChatMessage(
      localId: row['id'] as String,
      serverId: asInt(row['serverId']),
      clientMessageId: row['clientMessageId']?.toString(),
      ownerId: asInt(row['ownerId']) ?? 0,
      sessionUnitId: row['sessionUnitId'] as String,
      senderSessionUnitId: row['senderSessionUnitId']?.toString(),
      messageType: asInt(row['messageType']) ?? 0,
      state: row['state']?.toString() ?? 'received',
      score: asInt(row['score']) ?? 0,
      createdAt: asDate(row['createTime']),
      raw: Map<String, dynamic>.unmodifiable(raw),
    );
  }

  final String localId;
  final int? serverId;
  final String? clientMessageId;
  final int ownerId;
  final String sessionUnitId;
  final String? senderSessionUnitId;
  final int messageType;
  final String state;
  final int score;
  final DateTime? createdAt;
  final Map<String, dynamic> raw;

  bool get isMine => senderSessionUnitId == sessionUnitId;
  String get text {
    final content = asMap(raw['content']);
    return firstNonEmpty(<Object?>[
      content['text'],
      content['content'],
      raw['text'],
    ]);
  }

  ChatMessage copyWith({
    int? serverId,
    String? state,
    int? score,
    Map<String, dynamic>? raw,
  }) => ChatMessage(
    localId: localId,
    serverId: serverId ?? this.serverId,
    clientMessageId: clientMessageId,
    ownerId: ownerId,
    sessionUnitId: sessionUnitId,
    senderSessionUnitId: senderSessionUnitId,
    messageType: messageType,
    state: state ?? this.state,
    score: score ?? this.score,
    createdAt: createdAt,
    raw: raw ?? this.raw,
  );

  Map<String, Object?> toDatabaseValues() => <String, Object?>{
    'id': localId,
    'serverId': serverId,
    'score': score,
    'clientMessageId': clientMessageId,
    'ownerId': ownerId,
    'sessionUnitId': sessionUnitId,
    'senderSessionUnitId': senderSessionUnitId,
    'messageType': messageType,
    'state': state,
    'createTime': createdAt?.millisecondsSinceEpoch,
    'raw': encodeJson(raw),
  };
}
