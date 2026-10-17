import 'dart:convert';

/// 原生子窗口类型枚举
enum SubWindowType {
  chat,
  settings,
  browser,
  media,
  diagnostics,
  localFileServer,
}

/// 原生子窗口启动载荷（跨 Flutter 引擎序列化参数）
class NativeWindowPayload {
  const NativeWindowPayload({
    required this.type,
    required this.title,
    required this.targetId,
    this.sessionUnitId,
    this.ownerId,
    this.url,
    this.fallbackContent,
    this.initialIndex = 0,
    this.mediaItems,
    this.extra,
  });

  final SubWindowType type;
  final String title;
  final String targetId;
  final String? sessionUnitId;
  final int? ownerId;
  final String? url;
  final String? fallbackContent;
  final int initialIndex;
  final List<Map<String, dynamic>>? mediaItems;
  final Map<String, dynamic>? extra;

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'title': title,
      'targetId': targetId,
      if (sessionUnitId != null) 'sessionUnitId': sessionUnitId,
      if (ownerId != null) 'ownerId': ownerId,
      if (url != null) 'url': url,
      if (fallbackContent != null) 'fallbackContent': fallbackContent,
      'initialIndex': initialIndex,
      if (mediaItems != null) 'mediaItems': mediaItems,
      if (extra != null) 'extra': extra,
    };
  }

  String toJsonString() => jsonEncode(toJson());

  factory NativeWindowPayload.fromMap(Map<String, dynamic> map) {
    final typeStr = map['type'] as String? ?? '';
    final type = SubWindowType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => SubWindowType.settings,
    );
    final mediaItemsRaw = map['mediaItems'] as List<dynamic>?;
    final mediaItems = mediaItemsRaw
        ?.map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return NativeWindowPayload(
      type: type,
      title: map['title'] as String? ?? 'GotoIM',
      targetId: map['targetId'] as String? ?? 'sub_window',
      sessionUnitId: map['sessionUnitId'] as String?,
      ownerId: map['ownerId'] as int?,
      url: map['url'] as String?,
      fallbackContent: map['fallbackContent'] as String?,
      initialIndex: map['initialIndex'] as int? ?? 0,
      mediaItems: mediaItems,
      extra: map['extra'] as Map<String, dynamic>?,
    );
  }

  static NativeWindowPayload? tryParse(String? source) {
    if (source == null || source.trim().isEmpty) return null;
    try {
      final map = jsonDecode(source) as Map<String, dynamic>;
      return NativeWindowPayload.fromMap(map);
    } catch (_) {
      return null;
    }
  }
}
