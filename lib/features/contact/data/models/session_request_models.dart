/// 解析助手卡片等链接中的入群/加好友申请 ID。
/// 兼容历史后端拼写 `app://sesson-request/detail?id=...` 与标准拼写 `app://session-request/detail?id=...`。
String? parseSessionRequestDetailId(String rawUrl) {
  final trimmed = rawUrl.trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;
  if (uri.scheme.toLowerCase() != 'app') return null;
  final host = uri.host.toLowerCase();
  if (host != 'sesson-request' && host != 'session-request') return null;
  final normalizedPath = uri.path.toLowerCase().replaceAll(RegExp(r'^/+|/+$'), '');
  if (normalizedPath != 'detail') return null;
  final id = uri.queryParameters['id']?.trim();
  if (id == null || id.isEmpty) return null;
  return id;
}

class SessionRequestActor {
  const SessionRequestActor({
    required this.id,
    required this.name,
    this.code,
    this.avatar,
    this.objectType,
  });

  final int id;
  final String name;
  final String? code;
  final String? avatar;
  final int? objectType;

  factory SessionRequestActor.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final id = rawId is int ? rawId : int.tryParse('$rawId') ?? 0;
    final rawType = json['objectType'];
    final objectType = rawType is int ? rawType : int.tryParse('$rawType');
    final avatarRaw = json['thumbnail'] ?? json['portrait'];
    return SessionRequestActor(
      id: id,
      name: (json['name'] ?? json['fullPathName'] ?? '').toString(),
      code: json['code']?.toString(),
      avatar:
          avatarRaw != null && '$avatarRaw'.isNotEmpty ? '$avatarRaw' : null,
      objectType: objectType,
    );
  }
}

class SessionRequestItem {
  const SessionRequestItem({
    required this.id,
    required this.ownerId,
    required this.destinationId,
    required this.requestMessage,
    required this.handleMessage,
    required this.isAgreed,
    required this.isHandled,
    required this.isExpired,
    this.creationTime,
    this.handleTime,
    this.owner,
    this.destination,
  });

  final String id;
  final int ownerId;
  final int destinationId;
  final String requestMessage;
  final String handleMessage;
  final bool? isAgreed;
  final bool isHandled;
  final bool isExpired;
  final DateTime? creationTime;
  final DateTime? handleTime;
  final SessionRequestActor? owner;
  final SessionRequestActor? destination;

  factory SessionRequestItem.fromJson(Map<String, dynamic> json) {
    int parseInt(Object? v) => v is int ? v : int.tryParse('${v ?? ''}') ?? 0;
    bool? parseBoolNullable(Object? v) {
      if (v is bool) return v;
      if (v == null) return null;
      final lower = '$v'.toLowerCase();
      if (lower == 'true') return true;
      if (lower == 'false') return false;
      return null;
    }

    DateTime? parseDate(Object? v) {
      if (v == null) return null;
      return DateTime.tryParse('$v');
    }

    final ownerMap = json['owner'];
    final destMap = json['destination'];
    return SessionRequestItem(
      id: '${json['id'] ?? ''}',
      ownerId: parseInt(json['ownerId']),
      destinationId: parseInt(json['destinationId']),
      requestMessage: (json['requestMessage'] ?? '').toString(),
      handleMessage: (json['handleMessage'] ?? '').toString(),
      isAgreed: parseBoolNullable(json['isAgreed']),
      isHandled: json['isHandled'] == true,
      isExpired: json['isExpired'] == true,
      creationTime: parseDate(json['creationTime']),
      handleTime: parseDate(json['handleTime']),
      owner:
          ownerMap is Map
              ? SessionRequestActor.fromJson(
                Map<String, dynamic>.from(ownerMap),
              )
              : null,
      destination:
          destMap is Map
              ? SessionRequestActor.fromJson(Map<String, dynamic>.from(destMap))
              : null,
    );
  }
}
