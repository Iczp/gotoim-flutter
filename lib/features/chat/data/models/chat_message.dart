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
    final serverId = asInt(json['id']) ?? asInt(json['messageId']);
    final rawClientMessageId = json['clientMessageId']?.toString().trim();
    final clientId = (rawClientMessageId == null ||
            rawClientMessageId.isEmpty ||
            rawClientMessageId == 'null')
        ? null
        : rawClientMessageId;
    final sender = asMap(json['senderSessionUnit']);
    final effectiveLocalId = clientId ??
        (serverId != null
            ? 'server-$serverId'
            : '${DateTime.now().microsecondsSinceEpoch}');
    return ChatMessage(
      localId: effectiveLocalId,
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
    final rawClientId = row['clientMessageId']?.toString().trim();
    final clientId =
        (rawClientId == null || rawClientId.isEmpty || rawClientId == 'null')
            ? null
            : rawClientId;
    return ChatMessage(
      localId: row['id'] as String,
      serverId: asInt(row['serverId']),
      clientMessageId: clientId,
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
  bool get isOpened => raw['isOpened'] == true || isMine;
  Map<String, dynamic> get senderSessionUnit => asMap(raw['senderSessionUnit']);
  String get senderName {
    final sender = senderSessionUnit;
    final owner = asMap(sender['owner']);
    final name = firstNonEmpty(<Object?>[
      owner['fullPathName'],
      raw['senderName'],
      raw['senderDisplayName'],
      sender['displayName'],
      sender['memberName'],
      owner['displayName'],
      owner['name'],
      isMine ? '我' : '未知用户',
    ]);
    return name.replaceAll('/', ':');
  }

  String? get senderAvatarUrl {
    final sender = senderSessionUnit;
    final owner = asMap(sender['owner']);
    final value = firstNonEmpty(<Object?>[
      sender['thumbnail'],
      sender['portrait'],
      owner['thumbnail'],
      owner['portrait'],
    ]);
    return value.isEmpty ? null : value;
  }

  String get text {
    final content = asMap(raw['content']);
    return firstNonEmpty(<Object?>[
      content['text'],
      content['content'],
      raw['text'],
    ]);
  }

  Map<String, dynamic> get content => asMap(raw['content']);
  bool get isRollbacked =>
      raw['isRollbacked'] == true || raw['rollbackTime'] != null;
  int? get quoteMessageId => asInt(raw['quoteMessageId']);
  Map<String, dynamic> get quoteMessage => asMap(raw['quoteMessage']);
  String get quoteSenderName {
    final quote = quoteMessage;
    final sender = asMap(quote['senderSessionUnit']);
    final owner = asMap(sender['owner']);
    return firstNonEmpty(<Object?>[
      owner['fullPathName'],
      quote['senderName'],
      sender['displayName'],
      owner['displayName'],
      '未知用户',
    ]).replaceAll('/', ':');
  }

  String? get mediaUrl {
    final value = firstNonEmpty(<Object?>[
      content['url'],
      content['thumbnailUrl'],
      content['imageUrl'],
    ]);
    return value.isEmpty ? null : value;
  }

  /// Original media dimensions supplied by the message contract. Both image
  /// and video messages have used the generic and image-prefixed forms.
  double? get mediaAspectRatio {
    final width = asInt(content['imageWidth']) ??
        asInt(content['width']) ??
        asInt(content['videoWidth']);
    final height = asInt(content['imageHeight']) ??
        asInt(content['height']) ??
        asInt(content['videoHeight']);
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return width / height;
  }

  String get fileName =>
      firstNonEmpty(<Object?>[content['fileName'], content['name']]);
  int get fileSize => asInt(content['size']) ?? 0;
  Duration get audioDuration => Duration(
        milliseconds: asInt(content['time']) ??
            asInt(content['duration']) ??
            asInt(content['durationMs']) ??
            0,
      );
  String? get audioUrl {
    final value = firstNonEmpty(<Object?>[content['url'], content['audioUrl']]);
    return value.isEmpty ? null : value;
  }

  String get fileSuffix => firstNonEmpty(<Object?>[
        content['suffix'],
        fileName.contains('.') ? '.${fileName.split('.').last}' : '',
      ]);
  String? get localFilePath {
    final value = content['path']?.toString();
    return value == null || value.isEmpty ? null : value;
  }

  String get linkUrl =>
      firstNonEmpty(<Object?>[content['url'], content['link']]);
  String get linkTitle =>
      firstNonEmpty(<Object?>[content['title'], content['name'], linkUrl]);
  String get linkDescription =>
      firstNonEmpty(<Object?>[content['description'], content['content']]);
  String? get linkImageUrl {
    final value = firstNonEmpty(<Object?>[
      content['image'],
      content['thumbnail'],
    ]);
    return value.isEmpty ? null : value;
  }

  String get historyTitle => firstNonEmpty(<Object?>[content['title'], '聊天记录']);
  String get historyDescription =>
      firstNonEmpty(<Object?>[content['description'], content['content']]);

  ChatMessage copyWith({
    int? serverId,
    String? state,
    int? score,
    Map<String, dynamic>? raw,
  }) =>
      ChatMessage(
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
        'clientMessageId':
            (clientMessageId == null || clientMessageId!.trim().isEmpty)
                ? null
                : clientMessageId!.trim(),
        'ownerId': ownerId,
        'sessionUnitId': sessionUnitId,
        'senderSessionUnitId': senderSessionUnitId,
        'messageType': messageType,
        'state': state,
        'createTime': createdAt?.millisecondsSinceEpoch,
        'raw': encodeJson(raw),
      };
}
