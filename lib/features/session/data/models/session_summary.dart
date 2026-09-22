import 'session_summary_helpers.dart';

class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.ownerId,
    required this.score,
    this.sorting = 0,
    required this.ticks,
    required this.title,
    required this.preview,
    required this.updatedAt,
    required this.unreadCount,
    required this.isPinned,
    required this.raw,
    this.hasAuthoritativeScore = false,
    this.hasAuthoritativeSorting = false,
    this.hasAuthoritativeTicks = false,
  });

  factory SessionSummary.fromJson(Map<String, dynamic> json) {
    final destination = asMap(json['destination'] ?? json['Destination']);
    final lastMessage = asMap(json['lastMessage'] ?? json['LastMessage']);
    final setting = asMap(json['setting'] ?? json['Setting']);
    final title = firstNonEmpty(<Object?>[
      destination['displayName'] ?? destination['DisplayName'],
      destination['memberName'] ?? destination['MemberName'],
      destination['name'] ?? destination['Name'],
      destination['nickName'] ?? destination['NickName'],
      json['displayName'] ?? json['DisplayName'],
      json['destinationName'] ?? json['DestinationName'],
      json['title'] ?? json['Title'],
    ]);

    final hasAuthoritativeSorting =
        json.containsKey('sorting') || json.containsKey('Sorting');
    final hasAuthoritativeTicks =
        json.containsKey('ticks') || json.containsKey('Ticks');
    final hasAuthoritativeScore =
        json.containsKey('score') || json.containsKey('Score');
    final rawSorting =
        asInt(json['sorting'] ?? json['Sorting']) ??
        (setting['isTopping'] == true ||
                setting['isTop'] == true ||
                setting['IsTopping'] == true ||
                setting['IsTop'] == true
            ? 1
            : 0);
    final isPinned =
        rawSorting > 0 ||
        setting['isTopping'] == true ||
        setting['isTop'] == true ||
        setting['IsTopping'] == true ||
        setting['IsTop'] == true;
    final sorting = isPinned && rawSorting == 0 ? 1 : rawSorting;

    var ticks = asInt(json['ticks'] ?? json['Ticks']) ?? 0;
    if (ticks <= 0) {
      final date =
          asDate(json['lastMessageTime'] ?? json['LastMessageTime']) ??
          asDate(lastMessage['creationTime'] ?? lastMessage['CreationTime']) ??
          asDate(
            json['lastModificationTime'] ?? json['LastModificationTime'],
          ) ??
          asDate(json['creationTime'] ?? json['CreationTime']);
      if (date != null) {
        ticks = date.millisecondsSinceEpoch;
      }
    }

    final rawScore = asInt(json['score'] ?? json['Score']);
    // Score is the server's global ordering key. Some list responses have
    // returned a newer Score with an older Ticks value. Derive Ticks from the
    // documented FriendScore contract so display-time grouping cannot disagree
    // with the global list order: Score = Sorting * 1e13 + Ticks.
    if (rawScore != null && rawScore > 0) {
      final scoreTicks = rawScore - sorting * 10000000000000;
      if (scoreTicks >= 0 && scoreTicks != ticks) {
        ticks = scoreTicks;
      }
    }
    final score =
        (rawScore != null && rawScore > 0)
            ? rawScore
            : (sorting > 0 ? (sorting * 10000000000000 + ticks) : ticks);

    final normalizedRaw = <String, dynamic>{
      ...json,
      'score': score,
      'sorting': sorting,
      'ticks': ticks,
    };

    return SessionSummary(
      id: (json['id'] ?? json['Id'])?.toString() ?? '',
      ownerId: asInt(json['ownerId'] ?? json['OwnerId']),
      score: score,
      sorting: sorting,
      ticks: ticks,
      title: title.isEmpty ? '未命名会话' : title,
      preview: messageContentText(lastMessage),
      updatedAt:
          asDate(json['lastMessageTime'] ?? json['LastMessageTime']) ??
          asDate(lastMessage['creationTime'] ?? lastMessage['CreationTime']) ??
          asDate(
            json['lastModificationTime'] ?? json['LastModificationTime'],
          ) ??
          (ticks > 0 ? DateTime.fromMillisecondsSinceEpoch(ticks) : null),
      unreadCount: asInt(json['publicBadge'] ?? json['PublicBadge']) ?? 0,
      isPinned: isPinned,
      raw: Map<String, dynamic>.unmodifiable(normalizedRaw),
      hasAuthoritativeScore: hasAuthoritativeScore,
      hasAuthoritativeSorting: hasAuthoritativeSorting,
      hasAuthoritativeTicks: hasAuthoritativeTicks,
    );
  }

  /// Merges partial responses without losing the peer identity, newest message,
  /// or sorting/score state persisted in a local Friend.
  SessionSummary mergeWithLocal(SessionSummary? local) {
    if (local == null) return this;
    final remoteLastMessage = asMap(raw['lastMessage'] ?? raw['LastMessage']);
    final localLastMessage = asMap(
      local.raw['lastMessage'] ?? local.raw['LastMessage'],
    );
    final remoteDestination = asMap(raw['destination'] ?? raw['Destination']);
    final localDestination = asMap(
      local.raw['destination'] ?? local.raw['Destination'],
    );
    final remoteOwner = asMap(raw['owner'] ?? raw['Owner']);
    final localOwner = asMap(local.raw['owner'] ?? local.raw['Owner']);

    final mergedRaw = Map<String, dynamic>.from(raw);

    // 1. Last message comparison: keep whichever message is newer
    final remoteMsgId =
        asInt(remoteLastMessage['id'] ?? remoteLastMessage['Id']) ??
        asInt(raw['lastMessageId'] ?? raw['LastMessageId']) ??
        0;
    final localMsgId =
        asInt(localLastMessage['id'] ?? localLastMessage['Id']) ??
        asInt(local.raw['lastMessageId'] ?? local.raw['LastMessageId']) ??
        0;

    if (remoteLastMessage.isEmpty && localLastMessage.isNotEmpty) {
      mergedRaw['lastMessage'] = localLastMessage;
      mergedRaw['lastMessageTime'] =
          raw['lastMessageTime'] ??
          raw['LastMessageTime'] ??
          local.raw['lastMessageTime'] ??
          local.raw['LastMessageTime'];
    } else if (remoteLastMessage.isNotEmpty && localLastMessage.isNotEmpty) {
      if (localMsgId > remoteMsgId) {
        mergedRaw['lastMessage'] = localLastMessage;
        mergedRaw['lastMessageTime'] =
            local.raw['lastMessageTime'] ??
            local.raw['LastMessageTime'] ??
            raw['lastMessageTime'] ??
            raw['LastMessageTime'];
      }
    }

    // The list/detail endpoints own the complete FriendScore tuple.  A lower
    // server score is meaningful (for example, after cancelling a pin), so do
    // not retain a larger stale local value.  Partial state acknowledgements
    // such as set-read omit these fields and retain the local tuple instead.
    final useRemoteScoreTuple = hasConsistentAuthoritativeScoreTuple;
    final mergedScore = useRemoteScoreTuple ? score : local.score;
    mergedRaw['score'] = mergedScore;

    // 3. Ticks and sorting are the inputs to the server-owned score.
    final mergedTicks = useRemoteScoreTuple ? ticks : local.ticks;
    mergedRaw['ticks'] = mergedTicks;

    // 4. An explicit zero is authoritative: it means a pin was removed.
    final mergedSorting = useRemoteScoreTuple ? sorting : local.sorting;
    mergedRaw['sorting'] = mergedSorting;

    // 5. Destination & Owner
    if (remoteDestination.isEmpty && localDestination.isNotEmpty) {
      mergedRaw['destination'] = localDestination;
    } else if (remoteDestination.isNotEmpty && localDestination.isNotEmpty) {
      mergedRaw['destination'] = <String, dynamic>{
        ...localDestination,
        ...remoteDestination,
      };
    }
    if (remoteOwner.isEmpty && localOwner.isNotEmpty) {
      mergedRaw['owner'] = localOwner;
    }

    // 6. PublicBadge (unread count): do not restore unread badge if user already read latest message
    final localReadId =
        local.readMessageId ??
        asInt(local.raw['readMessageId'] ?? local.raw['ReadMessageId']) ??
        0;
    final effectiveLastMsgId =
        asInt(mergedRaw['lastMessageId'] ?? mergedRaw['LastMessageId']) ??
        asInt(
          asMap(mergedRaw['lastMessage'])['id'] ??
              asMap(mergedRaw['lastMessage'])['Id'],
        ) ??
        0;
    if (local.unreadCount == 0 &&
        localReadId >= effectiveLastMsgId &&
        effectiveLastMsgId > 0) {
      mergedRaw['publicBadge'] = 0;
    }

    return SessionSummary.fromJson(mergedRaw);
  }

  /// Fills a missing sender/current-side owner from the selected chat object.
  /// This must never replace `destination`, which is the remote AI/contact.
  SessionSummary withCurrentOwnerFallback(Map<String, dynamic>? currentObject) {
    if (currentObject == null ||
        currentObject.isEmpty ||
        asMap(raw['owner'] ?? raw['Owner']).isNotEmpty) {
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
    final rowOwnerId = asInt(row['ownerId']);
    final rowScore = asInt(row['score']);
    final rowSorting = asInt(row['sorting']);
    final rowTicks = asInt(row['ticks']);

    if (rowOwnerId != null) decoded['ownerId'] = rowOwnerId;
    if (rowScore != null && rowScore > 0) decoded['score'] = rowScore;
    if (rowSorting != null) decoded['sorting'] = rowSorting;
    if (rowTicks != null && rowTicks > 0) decoded['ticks'] = rowTicks;

    return SessionSummary.fromJson(decoded);
  }

  final String id;
  final int? ownerId;
  final int score;
  final int sorting;
  final int ticks;
  final String title;
  final String preview;
  final DateTime? updatedAt;
  final int unreadCount;
  final bool isPinned;
  final Map<String, dynamic> raw;
  final bool hasAuthoritativeScore;
  final bool hasAuthoritativeSorting;
  final bool hasAuthoritativeTicks;

  /// Friend list/detail responses must obey Score = Sorting * 1e13 + Ticks.
  bool get hasConsistentAuthoritativeScoreTuple =>
      hasAuthoritativeScore &&
      hasAuthoritativeSorting &&
      hasAuthoritativeTicks &&
      score == sorting * 10000000000000 + ticks;

  int? get lastMessageId =>
      asInt(
        asMap(raw['lastMessage'] ?? raw['LastMessage'])['id'] ??
            asMap(raw['lastMessage'] ?? raw['LastMessage'])['Id'],
      ) ??
      asInt(raw['lastMessageId'] ?? raw['LastMessageId']);
  int? get readMessageId => asInt(raw['readMessageId'] ?? raw['ReadMessageId']);
  int? get peerReadMessageId =>
      asInt(raw['peerReadMessageId'] ?? raw['PeerReadMessageId']);
  int? get ownerObjectType =>
      asInt(raw['ownerObjectType'] ?? raw['OwnerObjectType']) ??
      asInt(
        asMap(raw['owner'] ?? raw['Owner'])['objectType'] ??
            asMap(raw['owner'] ?? raw['Owner'])['ObjectType'],
      );
  int? get destinationId =>
      asInt(
        asMap(raw['destination'] ?? raw['Destination'])['id'] ??
            asMap(raw['destination'] ?? raw['Destination'])['Id'],
      ) ??
      asInt(raw['destinationId'] ?? raw['DestinationId']);

  /// 会话目标对象的头像链接。
  String? get avatarUrl {
    final destination = asMap(raw['destination'] ?? raw['Destination']);
    final value =
        destination['thumbnail'] ??
        destination['Thumbnail'] ??
        destination['portrait'] ??
        destination['Portrait'] ??
        raw['thumbnail'] ??
        raw['portrait'];
    return value?.toString();
  }

  /// The original client shows the transfer control for shopkeeper/waiter
  /// identities (7/8), not just when the chat destination is a shop account.
  bool get isShopkeeperOrWaiter => ownerObjectType == 7 || ownerObjectType == 8;
  int? get ownerParentId => asInt(
    asMap(raw['owner'] ?? raw['Owner'])['parentId'] ??
        asMap(raw['owner'] ?? raw['Owner'])['ParentId'],
  );

  /// Shop waiter accounts are children of a shopkeeper. The transfer list is
  /// scoped to that shopkeeper so a waiter can only hand over within its shop.
  int? get transferShopKeeperId =>
      ownerObjectType == 8 ? ownerParentId ?? ownerId : ownerId;

  bool get isImmersed {
    final value =
        asMap(raw['setting'] ?? raw['Setting'])['isImmersed'] ??
        asMap(raw['setting'] ?? raw['Setting'])['IsImmersed'];
    return value == true || asInt(value) == 1;
  }

  DateTime? get muteExpireTime => asDate(
    asMap(raw['setting'] ?? raw['Setting'])['muteExpireTime'] ??
        asMap(raw['setting'] ?? raw['Setting'])['MuteExpireTime'],
  );
  bool get isMuted =>
      muteExpireTime != null && muteExpireTime!.isAfter(DateTime.now());

  String get messageTypeLabel =>
      messageContentType(asMap(raw['lastMessage'] ?? raw['LastMessage']));

  Map<String, Object?> toDatabaseValues() => <String, Object?>{
    'id': id,
    'ownerId': ownerId,
    'score': score,
    'sorting': sorting,
    'ticks': ticks,
    'createTime': millis(raw['creationTime'] ?? raw['CreationTime']),
    'updateTime': updatedAt?.millisecondsSinceEpoch,
    'expireTime': millis(raw['expireTime'] ?? raw['ExpireTime']),
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
          sorting == other.sorting &&
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
    sorting,
    ticks,
    title,
    preview,
    updatedAt,
    unreadCount,
    isPinned,
  );
}
