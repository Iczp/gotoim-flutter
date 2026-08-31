import 'dart:async';

import '../platform/platform_contract.dart';

/// 通知服务对业务层暴露的统一契约；业务代码不需要知道具体插件或平台 API。
abstract class LocalNotificationService {
  LocalNotificationSupport get support;

  Stream<LocalNotificationTapEvent> get tapEvents;

  Future<void> initialize();

  Future<LocalNotificationPermissionResult> requestPermission();

  /// 立即展示，或在应用进程存活期间延迟展示一条本地通知。
  Future<LocalNotificationDispatchResult> show(
    LocalNotificationRequest request,
  );

  Future<void> cancel(int id);

  Future<void> cancelAll();

  Future<void> dispose();
}

class LocalNotificationSupport {
  const LocalNotificationSupport({
    required this.platform,
    required this.isSupported,
    required this.message,
  });

  final PlatformKind platform;
  final bool isSupported;
  final String message;
}

enum LocalNotificationPermissionStatus {
  granted,
  denied,
  notRequired,
  unsupported,
  unknown,
}

class LocalNotificationPermissionResult {
  const LocalNotificationPermissionResult({
    required this.status,
    required this.message,
  });

  final LocalNotificationPermissionStatus status;
  final String message;
}

/// 调试与业务通知共用的数据模型。
///
/// [delay] 是进程内延迟，不是操作系统持久化的定时通知；进程结束后不会触发。
class LocalNotificationRequest {
  const LocalNotificationRequest({
    required this.id,
    required this.channelId,
    required this.channelName,
    required this.title,
    required this.body,
    this.payload = '',
    this.delay = Duration.zero,
    this.ongoing = false,
    this.actions = const [],
  });

  final int id;
  final String channelId;
  final String channelName;
  final String title;
  final String body;
  final String payload;
  final Duration delay;

  /// Android uses this for a non-dismissible status notification while a
  /// long-running user-visible feature (such as LAN sharing) is active.
  final bool ongoing;

  /// Optional user actions. Unsupported platforms safely ignore them.
  final List<LocalNotificationAction> actions;
}

class LocalNotificationAction {
  const LocalNotificationAction({
    required this.id,
    required this.title,
    this.showsUserInterface = false,
  });

  final String id;
  final String title;

  /// Android actions that must execute application state changes should bring
  /// the app to foreground unless a dedicated background callback is supplied.
  final bool showsUserInterface;
}

enum LocalNotificationDispatchStatus { shown, queued, unsupported }

class LocalNotificationDispatchResult {
  const LocalNotificationDispatchResult({
    required this.status,
    required this.message,
  });

  final LocalNotificationDispatchStatus status;
  final String message;
}

/// 用户点击通知或通知动作后上报的、与插件无关的数据。
class LocalNotificationTapEvent {
  const LocalNotificationTapEvent({
    required this.receivedAt,
    required this.payload,
    this.actionId,
  });

  final DateTime receivedAt;
  final String payload;
  final String? actionId;
}
