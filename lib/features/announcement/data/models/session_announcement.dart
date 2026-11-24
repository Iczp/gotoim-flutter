class SessionAnnouncement {
  const SessionAnnouncement({
    required this.id,
    required this.sessionId,
    required this.chatObjectId,
    required this.publisherSessionUnitId,
    required this.publisherChatObjectId,
    required this.title,
    required this.content,
    required this.editorType,
    required this.status,
    required this.isPinned,
    required this.isPopup,
    required this.requireConfirm,
    required this.confirmedCount,
    required this.readCount,
    required this.creationTime,
    this.publisherName,
    this.publisherAvatar,
    this.sorting = 0,
    this.pinnedTime,
    this.expireTime,
    this.applyToNewMembers = false,
    this.isExpired = false,
    this.isEffectiveForCurrentUser = true,
    this.linkedMessageId,
    this.isSelfConfirmed = false,
    this.isSelfRead = false,
  });

  factory SessionAnnouncement.fromJson(Map<String, dynamic> json) {
    return SessionAnnouncement(
      id: json['id']?.toString() ?? '',
      sessionId: json['sessionId']?.toString() ?? '',
      chatObjectId: json['chatObjectId']?.toString() ?? '',
      publisherSessionUnitId: json['publisherSessionUnitId']?.toString() ?? '',
      publisherChatObjectId: json['publisherChatObjectId']?.toString() ?? '',
      publisherName: json['publisherName']?.toString(),
      publisherAvatar:
          json['publisherAvatar']?.toString() ?? json['publisherPortrait']?.toString(),
      title: json['title']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      editorType: (json['editorType'] as num?)?.toInt() ?? 0,
      status: (json['status'] as num?)?.toInt() ?? 1,
      isPinned: json['isPinned'] == true || ((json['sorting'] as num?)?.toDouble() ?? 0) > 0,
      sorting: (json['sorting'] as num?)?.toDouble() ?? 0,
      pinnedTime: json['pinnedTime']?.toString(),
      expireTime: json['expireTime']?.toString(),
      applyToNewMembers: json['applyToNewMembers'] == true,
      isExpired: json['isExpired'] == true,
      isEffectiveForCurrentUser: json['isEffectiveForCurrentUser'] != false,
      isPopup: json['isPopup'] == true,
      requireConfirm: json['requireConfirm'] == true,
      confirmedCount: (json['confirmedCount'] as num?)?.toInt() ?? 0,
      readCount: (json['readCount'] as num?)?.toInt() ?? 0,
      linkedMessageId: json['linkedMessageId']?.toString(),
      creationTime: json['creationTime']?.toString() ?? '',
      isSelfConfirmed:
          json['isSelfConfirmed'] == true || json['isConfirmedByCurrentUser'] == true,
      isSelfRead: json['isSelfRead'] == true,
    );
  }

  final String id;
  final String sessionId;
  final String chatObjectId;
  final String publisherSessionUnitId;
  final String publisherChatObjectId;
  final String? publisherName;
  final String? publisherAvatar;
  final String title;
  final String content;
  final int editorType;
  final int status;
  final bool isPinned;
  final double sorting;
  final String? pinnedTime;
  final String? expireTime;
  final bool applyToNewMembers;
  final bool isExpired;
  final bool isEffectiveForCurrentUser;
  final bool isPopup;
  final bool requireConfirm;
  final int confirmedCount;
  final int readCount;
  final String? linkedMessageId;
  final String creationTime;
  final bool isSelfConfirmed;
  final bool isSelfRead;

  SessionAnnouncement copyWith({
    bool? isPinned,
    String? pinnedTime,
    bool? isSelfConfirmed,
    int? confirmedCount,
    bool? isSelfRead,
    int? readCount,
  }) {
    return SessionAnnouncement(
      id: id,
      sessionId: sessionId,
      chatObjectId: chatObjectId,
      publisherSessionUnitId: publisherSessionUnitId,
      publisherChatObjectId: publisherChatObjectId,
      publisherName: publisherName,
      publisherAvatar: publisherAvatar,
      title: title,
      content: content,
      editorType: editorType,
      status: status,
      isPinned: isPinned ?? this.isPinned,
      sorting: sorting,
      pinnedTime: pinnedTime ?? this.pinnedTime,
      expireTime: expireTime,
      applyToNewMembers: applyToNewMembers,
      isExpired: isExpired,
      isEffectiveForCurrentUser: isEffectiveForCurrentUser,
      isPopup: isPopup,
      requireConfirm: requireConfirm,
      confirmedCount: confirmedCount ?? this.confirmedCount,
      readCount: readCount ?? this.readCount,
      linkedMessageId: linkedMessageId,
      creationTime: creationTime,
      isSelfConfirmed: isSelfConfirmed ?? this.isSelfConfirmed,
      isSelfRead: isSelfRead ?? this.isSelfRead,
    );
  }
}

class SessionAnnouncementStat {
  const SessionAnnouncementStat({
    required this.announcementId,
    required this.totalMemberCount,
    required this.readCount,
    required this.unreadCount,
    required this.confirmedCount,
    required this.unconfirmedCount,
    required this.readRate,
    required this.confirmedRate,
  });

  factory SessionAnnouncementStat.fromJson(Map<String, dynamic> json) {
    return SessionAnnouncementStat(
      announcementId: json['announcementId']?.toString() ?? '',
      totalMemberCount: (json['totalMemberCount'] as num?)?.toInt() ?? 0,
      readCount: (json['readCount'] as num?)?.toInt() ?? 0,
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
      confirmedCount: (json['confirmedCount'] as num?)?.toInt() ?? 0,
      unconfirmedCount: (json['unconfirmedCount'] as num?)?.toInt() ?? 0,
      readRate: (json['readRate'] as num?)?.toDouble() ?? 0.0,
      confirmedRate: (json['confirmedRate'] as num?)?.toDouble() ?? 0.0,
    );
  }

  final String announcementId;
  final int totalMemberCount;
  final int readCount;
  final int unreadCount;
  final int confirmedCount;
  final int unconfirmedCount;
  final double readRate;
  final double confirmedRate;
}

class SessionAnnouncementMember {
  const SessionAnnouncementMember({
    required this.sessionUnitId,
    required this.chatObjectId,
    required this.name,
    this.portrait,
    this.isConfirmed = false,
    this.confirmedTime,
    this.firstReadTime,
    this.isCreator = false,
    this.isAdmin = false,
  });

  factory SessionAnnouncementMember.fromJson(Map<String, dynamic> json) {
    return SessionAnnouncementMember(
      sessionUnitId: json['sessionUnitId']?.toString() ?? '',
      chatObjectId: json['chatObjectId']?.toString() ?? '',
      name: json['name']?.toString() ?? '成员',
      portrait: json['portrait']?.toString(),
      isConfirmed: json['isConfirmed'] == true,
      confirmedTime: json['confirmedTime']?.toString(),
      firstReadTime: json['firstReadTime']?.toString(),
      isCreator: json['isCreator'] == true,
      isAdmin: json['isAdmin'] == true,
    );
  }

  final String sessionUnitId;
  final String chatObjectId;
  final String name;
  final String? portrait;
  final bool isConfirmed;
  final String? confirmedTime;
  final String? firstReadTime;
  final bool isCreator;
  final bool isAdmin;
}
