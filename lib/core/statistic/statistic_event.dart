import 'dart:convert';
import 'package:uuid/uuid.dart';

/// 统计事件数据模型
class StatisticEvent {
  StatisticEvent({
    String? eventId,
    required this.eventName,
    this.sessionId,
    this.page,
    DateTime? eventTime,
    this.platform,
    this.appVersion,
    this.osVersion,
    this.channel,
    this.properties,
  })  : eventId = eventId ?? const Uuid().v4(),
        eventTime = eventTime ?? DateTime.now();

  final String eventId;
  final String eventName;
  final String? sessionId;
  final String? page;
  final DateTime eventTime;
  final String? platform;
  final String? appVersion;
  final String? osVersion;
  final String? channel;
  final Map<String, dynamic>? properties;

  /// 转为数据库存储行格式
  Map<String, Object?> toDbRow() {
    return <String, Object?>{
      'eventId': eventId,
      'eventName': eventName,
      'sessionId': sessionId,
      'page': page,
      'eventTime': eventTime.millisecondsSinceEpoch,
      'properties': properties != null ? jsonEncode(properties) : null,
    };
  }

  /// 从数据库行还原
  factory StatisticEvent.fromDbRow(Map<String, Object?> row) {
    Map<String, dynamic>? props;
    final rawProps = row['properties'] as String?;
    if (rawProps != null && rawProps.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawProps);
        if (decoded is Map) {
          props = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }

    return StatisticEvent(
      eventId: row['eventId'] as String,
      eventName: row['eventName'] as String,
      sessionId: row['sessionId'] as String?,
      page: row['page'] as String?,
      eventTime: DateTime.fromMillisecondsSinceEpoch(
        (row['eventTime'] as num).toInt(),
      ),
      properties: props,
    );
  }

  /// 转换为后端 EventItemDto 请求格式
  Map<String, dynamic> toApiDto({
    String? fallbackPlatform,
    String? fallbackAppVersion,
    String? fallbackOsVersion,
    String? fallbackChannel,
  }) {
    return <String, dynamic>{
      'eventId': eventId,
      'eventName': eventName,
      'sessionId': sessionId,
      'eventTime': eventTime.toIso8601String(),
      'page': page,
      'platform': platform ?? fallbackPlatform,
      'appVersion': appVersion ?? fallbackAppVersion,
      'osVersion': osVersion ?? fallbackOsVersion,
      'channel': channel ?? fallbackChannel,
      'properties': properties != null ? jsonEncode(properties) : null,
    };
  }

  StatisticEvent copyWith({
    String? eventId,
    String? eventName,
    String? sessionId,
    String? page,
    DateTime? eventTime,
    String? platform,
    String? appVersion,
    String? osVersion,
    String? channel,
    Map<String, dynamic>? properties,
  }) {
    return StatisticEvent(
      eventId: eventId ?? this.eventId,
      eventName: eventName ?? this.eventName,
      sessionId: sessionId ?? this.sessionId,
      page: page ?? this.page,
      eventTime: eventTime ?? this.eventTime,
      platform: platform ?? this.platform,
      appVersion: appVersion ?? this.appVersion,
      osVersion: osVersion ?? this.osVersion,
      channel: channel ?? this.channel,
      properties: properties ?? this.properties,
    );
  }

  @override
  String toString() {
    return 'StatisticEvent(eventId: $eventId, eventName: $eventName, page: $page, eventTime: $eventTime, props: $properties)';
  }
}
