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
    this.sessionName,
    this.sorting = 0,
    this.pinnedTime,
    this.expireTime,
    this.publishTime,
    this.applyToNewMembers = false,
    this.isExpired = false,
    this.isEffectiveForCurrentUser = true,
    this.linkedMessageId,
    this.isSelfConfirmed = false,
    this.isSelfRead = false,
    this.version = 1,
    this.isApproved = true,
    this.confirmedVersion = 0,
    this.reviewerSessionUnitId,
    this.reviewerChatObjectId,
    this.reviewerName,
    this.reviewerPortrait,
    this.reviewedTime,
    this.reviewRemark,
    this.canEdit = false,
    this.canDelete = false,
    this.canPublish = false,
    this.canSubmitReview = false,
    this.canApprove = false,
    this.canRevoke = false,
    this.canPin = false,
    this.canRemind = false,
    this.canViewStat = false,
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
      sessionName: json['sessionName']?.toString(),
      title: json['title']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      editorType: (json['editorType'] as num?)?.toInt() ?? 0,
      status: (json['status'] as num?)?.toInt() ?? 1,
      isPinned: json['isPinned'] == true || ((json['sorting'] as num?)?.toDouble() ?? 0) > 0,
      sorting: (json['sorting'] as num?)?.toDouble() ?? 0,
      pinnedTime: json['pinnedTime']?.toString(),
      expireTime: json['expireTime']?.toString(),
      publishTime: json['publishTime']?.toString(),
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
      version: (json['version'] as num?)?.toInt() ?? 1,
      isApproved: json['isApproved'] != false,
      confirmedVersion: (json['confirmedVersion'] as num?)?.toInt() ?? 0,
      reviewerSessionUnitId: json['reviewerSessionUnitId']?.toString(),
      reviewerChatObjectId: json['reviewerChatObjectId']?.toString(),
      reviewerName: json['reviewerName']?.toString(),
      reviewerPortrait: json['reviewerPortrait']?.toString(),
      reviewedTime: json['reviewedTime']?.toString(),
      reviewRemark: json['reviewRemark']?.toString(),
      canEdit: json['canEdit'] == true,
      canDelete: json['canDelete'] == true,
      canPublish: json['canPublish'] == true,
      canSubmitReview: json['canSubmitReview'] == true,
      canApprove: json['canApprove'] == true,
      canRevoke: json['canRevoke'] == true,
      canPin: json['canPin'] == true,
      canRemind: json['canRemind'] == true,
      canViewStat: json['canViewStat'] == true,
    );
  }

  final String id;
  final String sessionId;
  final String chatObjectId;
  final String publisherSessionUnitId;
  final String publisherChatObjectId;
  final String? publisherName;
  final String? publisherAvatar;
  final String? sessionName;
  final String title;
  final String content;
  final int editorType;
  final int status;
  final bool isPinned;
  final double sorting;
  final String? pinnedTime;
  final String? expireTime;
  final String? publishTime;
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
  final int version;
  final bool isApproved;
  final int confirmedVersion;
  final String? reviewerSessionUnitId;
  final String? reviewerChatObjectId;
  final String? reviewerName;
  final String? reviewerPortrait;
  final String? reviewedTime;
  final String? reviewRemark;
  final bool canEdit;
  final bool canDelete;
  final bool canPublish;
  final bool canSubmitReview;
  final bool canApprove;
  final bool canRevoke;
  final bool canPin;
  final bool canRemind;
  final bool canViewStat;

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
      sessionName: sessionName,
      title: title,
      content: content,
      editorType: editorType,
      status: status,
      isPinned: isPinned ?? this.isPinned,
      sorting: sorting,
      pinnedTime: pinnedTime ?? this.pinnedTime,
      expireTime: expireTime,
      publishTime: publishTime,
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
      version: version,
      isApproved: isApproved,
      confirmedVersion: confirmedVersion,
      reviewerSessionUnitId: reviewerSessionUnitId,
      reviewerChatObjectId: reviewerChatObjectId,
      reviewerName: reviewerName,
      reviewerPortrait: reviewerPortrait,
      reviewedTime: reviewedTime,
      reviewRemark: reviewRemark,
      canEdit: canEdit,
      canDelete: canDelete,
      canPublish: canPublish,
      canSubmitReview: canSubmitReview,
      canApprove: canApprove,
      canRevoke: canRevoke,
      canPin: canPin,
      canRemind: canRemind,
      canViewStat: canViewStat,
    );
  }
}

class SessionAnnouncementPermissions {
  const SessionAnnouncementPermissions({
    required this.sessionId,
    required this.sessionUnitId,
    this.isCreator = false,
    this.canCreate = false,
    this.canPublish = false,
    this.canApprove = false,
    this.canUpdateAny = false,
    this.canDeleteAny = false,
    this.canPin = false,
    this.canRemind = false,
    this.canViewStat = false,
    this.pendingReviewCount = 0,
    this.draftCount = 0,
  });

  factory SessionAnnouncementPermissions.fromJson(Map<String, dynamic> json) {
    return SessionAnnouncementPermissions(
      sessionId: json['sessionId']?.toString() ?? '',
      sessionUnitId: json['sessionUnitId']?.toString() ?? '',
      isCreator: json['isCreator'] == true,
      canCreate: json['canCreate'] == true,
      canPublish: json['canPublish'] == true,
      canApprove: json['canApprove'] == true,
      canUpdateAny: json['canUpdateAny'] == true,
      canDeleteAny: json['canDeleteAny'] == true,
      canPin: json['canPin'] == true,
      canRemind: json['canRemind'] == true,
      canViewStat: json['canViewStat'] == true,
      pendingReviewCount: (json['pendingReviewCount'] as num?)?.toInt() ?? 0,
      draftCount: (json['draftCount'] as num?)?.toInt() ?? 0,
    );
  }

  final String sessionId;
  final String sessionUnitId;
  final bool isCreator;
  final bool canCreate;
  final bool canPublish;
  final bool canApprove;
  final bool canUpdateAny;
  final bool canDeleteAny;
  final bool canPin;
  final bool canRemind;
  final bool canViewStat;
  final int pendingReviewCount;
  final int draftCount;

  bool get hasManagementRole =>
      isCreator || canApprove || canPublish || canUpdateAny || canDeleteAny;

  bool get hasManageEntry =>
      hasManagementRole || canCreate || draftCount > 0 || pendingReviewCount > 0;
}

class SessionAnnouncementRevision {
  const SessionAnnouncementRevision({
    required this.id,
    required this.announcementId,
    required this.version,
    required this.title,
    required this.content,
    required this.editorType,
    required this.editorSessionUnitId,
    required this.editorChatObjectId,
    required this.creationTime,
    this.editorName,
    this.editorPortrait,
    this.changeSummary,
  });

  factory SessionAnnouncementRevision.fromJson(Map<String, dynamic> json) {
    return SessionAnnouncementRevision(
      id: json['id']?.toString() ?? '',
      announcementId: json['announcementId']?.toString() ?? '',
      version: (json['version'] as num?)?.toInt() ?? 1,
      title: json['title']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      editorType: (json['editorType'] as num?)?.toInt() ?? 0,
      editorSessionUnitId: json['editorSessionUnitId']?.toString() ?? '',
      editorChatObjectId: json['editorChatObjectId']?.toString() ?? '',
      editorName: json['editorName']?.toString(),
      editorPortrait: json['editorPortrait']?.toString(),
      changeSummary: json['changeSummary']?.toString(),
      creationTime: json['creationTime']?.toString() ?? '',
    );
  }

  final String id;
  final String announcementId;
  final int version;
  final String title;
  final String content;
  final int editorType;
  final String editorSessionUnitId;
  final String editorChatObjectId;
  final String? editorName;
  final String? editorPortrait;
  final String? changeSummary;
  final String creationTime;
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
    final total =
        (json['totalMembersCount'] as num?)?.toInt() ??
        (json['totalMemberCount'] as num?)?.toInt() ??
        0;
    final confirmed = (json['confirmedCount'] as num?)?.toInt() ?? 0;
    return SessionAnnouncementStat(
      announcementId: json['announcementId']?.toString() ?? '',
      totalMemberCount: total,
      readCount: (json['readCount'] as num?)?.toInt() ?? 0,
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
      confirmedCount: confirmed,
      unconfirmedCount:
          (json['unconfirmedCount'] as num?)?.toInt() ??
          (total - confirmed).clamp(0, 999999),
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

  double get readPercent => readRate <= 1.0 ? readRate * 100 : readRate;

  double get confirmedPercent =>
      confirmedRate <= 1.0 ? confirmedRate * 100 : confirmedRate;
}

String? _firstNonEmptyString(List<Object?> candidates) {
  for (final candidate in candidates) {
    final text = candidate?.toString().trim() ?? '';
    if (text.isNotEmpty && text != 'null') return text;
  }
  return null;
}

class SessionAnnouncementMember {
  const SessionAnnouncementMember({
    required this.sessionUnitId,
    required this.chatObjectId,
    required this.name,
    this.portrait,
    this.isRead = false,
    this.isConfirmed = false,
    this.confirmedTime,
    this.firstReadTime,
    this.isCreator = false,
    this.isAdmin = false,
  });

  factory SessionAnnouncementMember.fromJson(Map<String, dynamic> json) {
    final firstReadTime = json['firstReadTime']?.toString();
    return SessionAnnouncementMember(
      sessionUnitId: json['sessionUnitId']?.toString() ?? '',
      chatObjectId: json['chatObjectId']?.toString() ?? '',
      name:
          _firstNonEmptyString([
            json['memberName'],
            json['name'],
            json['displayName'],
          ]) ??
          '成员',
      portrait: _firstNonEmptyString([
        json['memberPortrait'],
        json['portrait'],
        json['avatar'],
        json['thumbnail'],
      ]),
      isRead: json['isRead'] == true || firstReadTime != null,
      isConfirmed: json['isConfirmed'] == true,
      confirmedTime: json['confirmedTime']?.toString(),
      firstReadTime: firstReadTime,
      isCreator: json['isCreator'] == true,
      isAdmin: json['isAdmin'] == true,
    );
  }

  final String sessionUnitId;
  final String chatObjectId;
  final String name;
  final String? portrait;
  final bool isRead;
  final bool isConfirmed;
  final String? confirmedTime;
  final String? firstReadTime;
  final bool isCreator;
  final bool isAdmin;
}
