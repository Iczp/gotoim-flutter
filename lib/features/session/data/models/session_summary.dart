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

  /// Merges partial responses without losing the peer identity persisted in a
  /// local Friend. `owner` is the sending/current side; the remote chat peer
  /// is `destination`. A full `/friend/{id}` response replaces these fields.
  SessionSummary mergeWithLocal(SessionSummary? local) {
    if (local == null) return this;
    final remoteLastMessage = asMap(raw['lastMessage']);
    final localLastMessage = asMap(local.raw['lastMessage']);
    final remoteDestination = asMap(raw['destination']);
    final localDestination = asMap(local.raw['destination']);
    final needsLastMessage =
        remoteLastMessage.isEmpty && localLastMessage.isNotEmpty;
    final needsDestination =
        remoteDestination.isEmpty && localDestination.isNotEmpty;
    if (!needsLastMessage && !needsDestination) {
      return this;
    }
    final mergedRaw = Map<String, dynamic>.from(raw);
    if (needsLastMessage) {
      mergedRaw['lastMessage'] = localLastMessage;
      mergedRaw['lastMessageTime'] =
          raw['lastMessageTime'] ?? local.raw['lastMessageTime'];
    }
    if (needsDestination) mergedRaw['destination'] = localDestination;
    return SessionSummary.fromJson(mergedRaw);
  }

  /// Fills a missing sender/current-side owner from the selected chat object.
  /// This must never replace `destination`, which is the remote AI/contact.
  SessionSummary withCurrentOwnerFallback(Map<String, dynamic>? currentObject) {
    if (currentObject == null ||
        currentObject.isEmpty ||
        asMap(raw['owner']).isNotEmpty) {
      return this;
    }
    return SessionSummary.fromJson(<String, dynamic>{
      ...raw,
      'owner': currentObject,
    });
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
  int? get readMessageId => asInt(raw['readMessageId']);
  int? get peerReadMessageId => asInt(raw['peerReadMessageId']);
  int? get ownerObjectType =>
      asInt(raw['ownerObjectType']) ?? asInt(asMap(raw['owner'])['objectType']);

  /// The original client shows the transfer control for shopkeeper/waiter
  /// identities (7/8), not just when the chat destination is a shop account.
  bool get isShopkeeperOrWaiter => ownerObjectType == 7 || ownerObjectType == 8;
  int? get ownerParentId => asInt(asMap(raw['owner'])['parentId']);

  /// Shop waiter accounts are children of a shopkeeper. The transfer list is
  /// scoped to that shopkeeper so a waiter can only hand over within its shop.
  int? get transferShopKeeperId =>
      ownerObjectType == 8 ? ownerParentId ?? ownerId : ownerId;

  bool get isImmersed {
    final value = asMap(raw['setting'])['isImmersed'];
    return value == true || asInt(value) == 1;
  }

  DateTime? get muteExpireTime =>
      asDate(asMap(raw['setting'])['muteExpireTime']);
  bool get isMuted =>
      muteExpireTime != null && muteExpireTime!.isAfter(DateTime.now());

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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionSummary &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          ownerId == other.ownerId &&
          score == other.score &&
          ticks == other.ticks &&
          title == other.title &&
          preview == other.preview &&
          updatedAt == other.updatedAt &&
          unreadCount == other.unreadCount &&
          isPinned == other.isPinned;

  @override
  int get hashCode => Object.hash(
    id,
    ownerId,
    score,
    ticks,
    title,
    preview,
    updatedAt,
    unreadCount,
    isPinned,
  );
}
