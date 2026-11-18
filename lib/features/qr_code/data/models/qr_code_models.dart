enum QrCodeScene {
  chatObjectCard(1),
  groupInvite(2),
  workbenchApp(3),
  customPayload(99);

  const QrCodeScene(this.value);
  final int value;

  static QrCodeScene fromInt(int? value) {
    return QrCodeScene.values.firstWhere(
      (e) => e.value == value,
      orElse: () => QrCodeScene.chatObjectCard,
    );
  }
}

int? _parseInt(Object? raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse('$raw');
}

DateTime? _parseDateTime(Object? raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  return DateTime.tryParse('$raw');
}

class QrCodeDetailModel {
  const QrCodeDetailModel({
    required this.id,
    required this.code,
    required this.scene,
    this.title,
    this.content,
    this.ownerId,
    this.ownerObjectType,
    this.inviterId,
    required this.isPermanent,
    this.expireDays,
    this.expirationTime,
    required this.isEnabled,
    required this.isExpired,
    this.maxUseCount,
    this.usedCount = 0,
    this.payloadJson,
    this.ownerName,
    this.ownerCode,
    this.ownerPortrait,
    this.ownerThumbnail,
    this.inviterName,
  });

  factory QrCodeDetailModel.fromJson(Map<String, dynamic> json) {
    return QrCodeDetailModel(
      id: (json['id'] ?? '').toString(),
      code: (json['code'] ?? '').toString(),
      scene: QrCodeScene.fromInt(_parseInt(json['scene'])),
      title: json['title']?.toString(),
      content: json['content']?.toString(),
      ownerId: _parseInt(json['ownerId']),
      ownerObjectType: _parseInt(json['ownerObjectType']),
      inviterId: _parseInt(json['inviterId']),
      isPermanent: json['isPermanent'] == true,
      expireDays: _parseInt(json['expireDays']),
      expirationTime: _parseDateTime(json['expirationTime']),
      isEnabled: json['isEnabled'] != false,
      isExpired: json['isExpired'] == true,
      maxUseCount: _parseInt(json['maxUseCount']),
      usedCount: _parseInt(json['usedCount']) ?? 0,
      payloadJson: json['payloadJson']?.toString(),
      ownerName: json['ownerName']?.toString(),
      ownerCode: json['ownerCode']?.toString(),
      ownerPortrait: json['ownerPortrait']?.toString(),
      ownerThumbnail: json['ownerThumbnail']?.toString(),
      inviterName: json['inviterName']?.toString(),
    );
  }

  final String id;
  final String code;
  final QrCodeScene scene;
  final String? title;
  final String? content;
  final int? ownerId;
  final int? ownerObjectType;
  final int? inviterId;
  final bool isPermanent;
  final int? expireDays;
  final DateTime? expirationTime;
  final bool isEnabled;
  final bool isExpired;
  final int? maxUseCount;
  final int usedCount;
  final String? payloadJson;
  final String? ownerName;
  final String? ownerCode;
  final String? ownerPortrait;
  final String? ownerThumbnail;
  final String? inviterName;

  String get effectiveContent =>
      (content != null && content!.isNotEmpty) ? content! : 'gotoim://qr/$code';
}

class QrCodeScanDataModel {
  const QrCodeScanDataModel({
    this.qrCodeId,
    required this.code,
    required this.scene,
    required this.action,
    required this.isValid,
    required this.isExpired,
    required this.isDisabled,
    this.invalidReason,
    required this.isPermanent,
    this.expireDays,
    this.expirationTime,
    this.ownerId,
    this.ownerName,
    this.ownerCode,
    this.ownerPortrait,
    this.ownerThumbnail,
    this.ownerObjectType,
    this.ownerObjectTypeDescription,
    this.gender,
    this.description,
    this.verificationMethod,
    required this.needsApproval,
    this.inviterId,
    this.inviterName,
    this.memberCount,
    this.viewerChatObjectId,
    required this.isSelf,
    required this.isFriend,
    required this.isAlreadyMember,
    this.sessionUnitId,
    this.sessionId,
    this.payloadJson,
  });

  factory QrCodeScanDataModel.fromJson(Map<String, dynamic> json) {
    return QrCodeScanDataModel(
      qrCodeId: json['qrCodeId']?.toString(),
      code: (json['code'] ?? '').toString(),
      scene: QrCodeScene.fromInt(_parseInt(json['scene'])),
      action: (json['action'] ?? '').toString(),
      isValid: json['isValid'] == true,
      isExpired: json['isExpired'] == true,
      isDisabled: json['isDisabled'] == true,
      invalidReason: json['invalidReason']?.toString(),
      isPermanent: json['isPermanent'] == true,
      expireDays: _parseInt(json['expireDays']),
      expirationTime: _parseDateTime(json['expirationTime']),
      ownerId: _parseInt(json['ownerId']),
      ownerName: json['ownerName']?.toString(),
      ownerCode: json['ownerCode']?.toString(),
      ownerPortrait: json['ownerPortrait']?.toString(),
      ownerThumbnail: json['ownerThumbnail']?.toString(),
      ownerObjectType: _parseInt(json['ownerObjectType']),
      ownerObjectTypeDescription: json['ownerObjectTypeDescription']?.toString(),
      gender: _parseInt(json['gender']),
      description: json['description']?.toString(),
      verificationMethod: _parseInt(json['verificationMethod']),
      needsApproval: json['needsApproval'] == true,
      inviterId: _parseInt(json['inviterId']),
      inviterName: json['inviterName']?.toString(),
      memberCount: _parseInt(json['memberCount']),
      viewerChatObjectId: _parseInt(json['viewerChatObjectId']),
      isSelf: json['isSelf'] == true,
      isFriend: json['isFriend'] == true,
      isAlreadyMember: json['isAlreadyMember'] == true,
      sessionUnitId: json['sessionUnitId']?.toString(),
      sessionId: json['sessionId']?.toString(),
      payloadJson: json['payloadJson']?.toString(),
    );
  }

  final String? qrCodeId;
  final String code;
  final QrCodeScene scene;
  final String action;
  final bool isValid;
  final bool isExpired;
  final bool isDisabled;
  final String? invalidReason;
  final bool isPermanent;
  final int? expireDays;
  final DateTime? expirationTime;
  final int? ownerId;
  final String? ownerName;
  final String? ownerCode;
  final String? ownerPortrait;
  final String? ownerThumbnail;
  final int? ownerObjectType;
  final String? ownerObjectTypeDescription;
  final int? gender;
  final String? description;
  final int? verificationMethod;
  final bool needsApproval;
  final int? inviterId;
  final String? inviterName;
  final int? memberCount;
  final int? viewerChatObjectId;
  final bool isSelf;
  final bool isFriend;
  final bool isAlreadyMember;
  final String? sessionUnitId;
  final String? sessionId;
  final String? payloadJson;

  bool get isGroup =>
      action == 'group_invite' || scene == QrCodeScene.groupInvite;

  bool get isCardOrGroup =>
      action == 'chat_object_card' || action == 'group_invite';
}

class QrCodeApplyOutputModel {
  const QrCodeApplyOutputModel({
    required this.status,
    this.message,
    this.sessionUnitId,
    this.sessionId,
    this.sessionRequestId,
    this.targetChatObjectId,
  });

  factory QrCodeApplyOutputModel.fromJson(Map<String, dynamic> json) {
    return QrCodeApplyOutputModel(
      status: (json['status'] ?? '').toString(),
      message: json['message']?.toString(),
      sessionUnitId: json['sessionUnitId']?.toString(),
      sessionId: json['sessionId']?.toString(),
      sessionRequestId: json['sessionRequestId']?.toString(),
      targetChatObjectId: _parseInt(json['targetChatObjectId']),
    );
  }

  final String status;
  final String? message;
  final String? sessionUnitId;
  final String? sessionId;
  final String? sessionRequestId;
  final int? targetChatObjectId;
}

class ScanCodeHandlerResultModel {
  const ScanCodeHandlerResultModel({
    required this.handler,
    this.handlerFullName,
    required this.success,
    this.action,
    this.message,
    this.result,
  });

  factory ScanCodeHandlerResultModel.fromJson(Map<String, dynamic> json) {
    return ScanCodeHandlerResultModel(
      handler: (json['handler'] ?? '').toString(),
      handlerFullName: json['handlerFullName']?.toString(),
      success: json['success'] == true,
      action: json['action']?.toString(),
      message: json['message']?.toString(),
      result: json['result']?.toString(),
    );
  }

  final String handler;
  final String? handlerFullName;
  final bool success;
  final String? action;
  final String? message;
  final String? result;
}

class ScanCodeResultModel {
  const ScanCodeResultModel({
    this.type,
    this.content,
    this.execution = 0,
    this.handlerCount = 0,
    this.scanHandlers = const <ScanCodeHandlerResultModel>[],
  });

  factory ScanCodeResultModel.fromJson(Map<String, dynamic> json) {
    final rawHandlers = json['scanHandlers'];
    final handlers = rawHandlers is List
        ? rawHandlers
            .whereType<Map<String, dynamic>>()
            .map(ScanCodeHandlerResultModel.fromJson)
            .toList()
        : const <ScanCodeHandlerResultModel>[];

    return ScanCodeResultModel(
      type: json['type']?.toString(),
      content: json['content']?.toString(),
      execution: (json['execution'] as num?)?.toDouble() ?? 0,
      handlerCount: _parseInt(json['handlerCount']) ?? handlers.length,
      scanHandlers: handlers,
    );
  }

  final String? type;
  final String? content;
  final double execution;
  final int handlerCount;
  final List<ScanCodeHandlerResultModel> scanHandlers;
}
