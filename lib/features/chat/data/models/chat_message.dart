import '../../../session/data/models/session_summary_helpers.dart';
import 'article_message_item.dart';
import 'template_message_content.dart';

/// 后端 `compactSenders=true` 时，分页结果在 `extra.senders` 以去重字典下发发送人，
/// 消息行内的 `senderSessionUnit` 被置空。此函数把字典回填到每条消息（含引用消息），
/// 使后续 [ChatMessage.fromJson] 与旧协议完全一致；没有字典时原样返回。
Map<String, dynamic> hydrateCompactSenders(Map<String, dynamic> page) {
  final extra = page['extra'];
  final rawSenders = extra is Map ? (extra['senders'] ?? extra['Senders']) : null;
  final items = page['items'];
  if (rawSenders is! Map || rawSenders.isEmpty || items is! List) return page;
  final senders = <String, Map<String, dynamic>>{
    for (final entry in rawSenders.entries)
      if (entry.value is Map)
        entry.key.toString().toLowerCase():
            Map<String, dynamic>.from(entry.value as Map),
  };
  Map<String, dynamic> fill(Map<String, dynamic> row) {
    final result = Map<String, dynamic>.from(row);
    final unitId = row['senderSessionUnitId']?.toString().toLowerCase();
    if (asMap(row['senderSessionUnit']).isEmpty &&
        unitId != null &&
        senders.containsKey(unitId)) {
      result['senderSessionUnit'] = senders[unitId];
    }
    final quote = row['quoteMessage'];
    if (quote is Map) {
      final quoteMap = Map<String, dynamic>.from(quote);
      final quoteUnit = quoteMap['senderSessionUnitId']?.toString().toLowerCase();
      if (asMap(quoteMap['senderSessionUnit']).isEmpty &&
          quoteUnit != null &&
          senders.containsKey(quoteUnit)) {
        quoteMap['senderSessionUnit'] = senders[quoteUnit];
      }
      result['quoteMessage'] = quoteMap;
    }
    return result;
  }

  return <String, dynamic>{
    ...page,
    'items': [
      for (final item in items)
        if (item is Map) fill(Map<String, dynamic>.from(item)) else item,
    ],
  };
}

/// 还原 `/api/chat/message/by-ids` 开启 `compactSenders=true` 时顶层 `senders` 字典到各状态行的 `message` 内。
Map<String, dynamic> hydrateByIdsCompactSenders(Map<String, dynamic> response) {
  final rawSenders = response['senders'] ?? response['Senders'];
  final items = response['items'];
  if (rawSenders is! Map || rawSenders.isEmpty || items is! List) {
    return response;
  }
  final fakeExtraPage = <String, dynamic>{
    'extra': <String, dynamic>{'senders': rawSenders},
    'items': [
      for (final row in items)
        if (row is Map && row['message'] is Map) row['message'],
    ],
  };
  final hydratedMessages = (hydrateCompactSenders(fakeExtraPage)['items'] as List)
      .cast<Map<String, dynamic>>();
  var idx = 0;
  return <String, dynamic>{
    ...response,
    'items': [
      for (final row in items)
        if (row is Map && row['message'] is Map)
          <String, dynamic>{
            ...Map<String, dynamic>.from(row),
            'message': hydratedMessages[idx++],
          }
        else
          row,
    ],
  };
}

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
    final clientId =
        (rawClientMessageId == null ||
                rawClientMessageId.isEmpty ||
                rawClientMessageId == 'null')
            ? null
            : rawClientMessageId;
    final sender = asMap(json['senderSessionUnit']);
    final remoteIdentity =
        (clientId ??
            (serverId != null
                ? 'server-$serverId'
                : '${DateTime.now().microsecondsSinceEpoch}'));
    final effectiveLocalId = 'scope:$ownerId:$sessionUnitId:$remoteIdentity';
    return ChatMessage(
      localId: effectiveLocalId,
      serverId: serverId,
      clientMessageId: clientId,
      ownerId: ownerId,
      sessionUnitId: sessionUnitId,
      senderSessionUnitId:
          sender['id']?.toString() ?? json['senderSessionUnitId']?.toString(),
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

  Map<String, dynamic> toWindowPayload() => {
    'id': localId,
    'serverId': serverId,
    'clientMessageId': clientMessageId,
    'ownerId': ownerId,
    'sessionUnitId': sessionUnitId,
    'senderSessionUnitId': senderSessionUnitId,
    'messageType': messageType,
    'state': state,
    'score': score,
    'time': createdAt?.millisecondsSinceEpoch,
    'text': text,
    'isMe': isMine,
    'raw': raw,
  };

  factory ChatMessage.fromWindowPayload(Map map) => ChatMessage(
    localId: map['id'] as String,
    serverId: (map['serverId'] as num?)?.toInt(),
    clientMessageId: map['clientMessageId'] as String?,
    ownerId: (map['ownerId'] as num?)?.toInt() ?? 0,
    sessionUnitId: map['sessionUnitId'] as String,
    senderSessionUnitId: map['senderSessionUnitId'] as String?,
    messageType: (map['messageType'] as num?)?.toInt() ?? 0,
    state: map['state'] as String? ?? 'received',
    score: (map['score'] as num?)?.toInt() ?? 0,
    createdAt:
        map['time'] is num
            ? DateTime.fromMillisecondsSinceEpoch((map['time'] as num).toInt())
            : null,
    raw: Map<String, dynamic>.from(map['raw'] as Map? ?? const {}),
  );

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

  bool get isMine =>
      (senderSessionUnitId != null && senderSessionUnitId == sessionUnitId) ||
      state == 'sending' ||
      state == 'pending';
  bool get isOpened => raw['isOpened'] == true || isMine;
  List<ArticleMessageItem> get articleItems =>
      ArticleMessageItem.fromContent(raw['content']);

  /// 发送失败的错误原因（若未失败或无错误信息则为 null）
  String? get errorMessage {
    final msg = raw['errorMessage'] ?? raw['error'] ?? raw['errorDescription'];
    if (msg == null) return null;
    final str = msg.toString().trim();
    return str.isEmpty ? null : str;
  }

  Map<String, dynamic> get senderSessionUnit => asMap(raw['senderSessionUnit']);
  int? get senderChatObjectId =>
      asInt(asMap(senderSessionUnit['owner'])['id']) ??
      asInt(senderSessionUnit['ownerId']);
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
    if (messageType == 13) return templateFallbackText(content['fallbackText']);
    return firstNonEmpty(<Object?>[
      content['text'],
      content['content'],
      content['fallbackText'],
      raw['text'],
    ]);
  }

  Map<String, dynamic> get content => asMap(raw['content']);
  bool get isRollbacked =>
      raw['isRollbacked'] == true || raw['rollbackTime'] != null;
  bool get isDeleted => raw['isDeleted'] == true;
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
      content['videoUrl'],
      content['imageUrl'],
      content['attachmentUrl'],
      content['fileUrl'],
      content['downloadUrl'],
      content['actionUrl'],
      content['thumbnailUrl'],
    ]);
    return value.isEmpty ? null : value;
  }

  String? get thumbnailUrl {
    final value = firstNonEmpty(<Object?>[
      content['thumbnailUrl'],
      content['snapshotThumbnailUrl'],
      content['snapshotUrl'],
      content['thumbnail'],
      content['coverUrl'],
    ]);
    return value.isEmpty ? null : value;
  }

  String? get videoCoverUrl {
    final value = firstNonEmpty(<Object?>[
      content['snapshotThumbnailUrl'],
      content['snapshotUrl'],
      content['coverUrl'],
      content['thumbnailUrl'],
      content['thumbnail'],
    ]);
    return value.isEmpty ? null : value;
  }

  String? get videoGifUrl {
    final value = firstNonEmpty(<Object?>[content['gifUrl']]);
    return value.isEmpty ? null : value;
  }

  static int? _positiveInt(Object? value) {
    final parsed = asInt(value);
    return parsed != null && parsed > 0 ? parsed : null;
  }

  /// Original media dimensions supplied by the message contract. Both image
  /// and video messages have used the generic and image-prefixed forms.
  double? get mediaAspectRatio {
    final width =
        _positiveInt(content['imageWidth']) ??
        _positiveInt(content['width']) ??
        _positiveInt(content['videoWidth']);
    final height =
        _positiveInt(content['imageHeight']) ??
        _positiveInt(content['height']) ??
        _positiveInt(content['videoHeight']);
    if (width == null || height == null) {
      return null;
    }
    return width / height;
  }

  String get fileName =>
      firstNonEmpty(<Object?>[content['fileName'], content['name']]);
  int get fileSize => asInt(content['size']) ?? 0;
  Duration get audioDuration => Duration(
    milliseconds:
        asInt(content['time']) ??
        asInt(content['duration']) ??
        asInt(content['durationMs']) ??
        0,
  );
  Duration? get videoDuration {
    final raw =
        asInt(content['duration']) ??
        asInt(content['durationSeconds']) ??
        asInt(content['time']);
    if (raw != null && raw > 0) {
      if (raw > 10000) {
        return Duration(milliseconds: raw);
      }
      return Duration(seconds: raw);
    }
    final rawMs = asInt(content['durationMs']);
    if (rawMs != null && rawMs > 0) {
      return Duration(milliseconds: rawMs);
    }
    return null;
  }

  String? get audioUrl {
    final value = firstNonEmpty(<Object?>[content['url'], content['audioUrl']]);
    return value.isEmpty ? null : value;
  }

  String get fileSuffix => firstNonEmpty(<Object?>[
    content['suffix'],
    fileName.contains('.') ? '.${fileName.split('.').last}' : '',
  ]);
  String? get localFilePath {
    final value =
        content['path']?.toString() ?? raw['localFilePath']?.toString();
    return value == null || value.isEmpty ? null : value;
  }

  String? get localThumbnailPath {
    final value = content['localThumbnailPath']?.toString();
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
