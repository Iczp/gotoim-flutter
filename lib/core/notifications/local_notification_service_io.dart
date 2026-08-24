import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../platform/platform_facade.dart';
import 'local_notification_contract.dart';

LocalNotificationService createLocalNotificationService({
  required PlatformFacade platformFacade,
}) => FlutterLocalNotificationService(platformFacade: platformFacade);

/// 唯一允许依赖 flutter_local_notifications 的适配器。
class FlutterLocalNotificationService implements LocalNotificationService {
  FlutterLocalNotificationService({
    required PlatformFacade platformFacade,
    FlutterLocalNotificationsPlugin? plugin,
  }) : _platformFacade = platformFacade,
       _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final PlatformFacade _platformFacade;
  final FlutterLocalNotificationsPlugin _plugin;
  final StreamController<LocalNotificationTapEvent> _tapEvents =
      StreamController<LocalNotificationTapEvent>.broadcast();
  final Map<int, Timer> _delayedNotifications = <int, Timer>{};
  bool _initialized = false;
  String? _initializationError;

  @override
  LocalNotificationSupport get support {
    if (_initializationError != null) {
      return LocalNotificationSupport(
        platform: _platformFacade.kind,
        isSupported: false,
        message: '本地通知初始化失败：$_initializationError',
      );
    }
    switch (_platformFacade.kind) {
      case PlatformKind.android:
      case PlatformKind.ios:
      case PlatformKind.macos:
      case PlatformKind.linux:
      case PlatformKind.windows:
        return LocalNotificationSupport(
          platform: _platformFacade.kind,
          isSupported: true,
          message: '本地通知已接入。',
        );
      case PlatformKind.web:
        return const LocalNotificationSupport(
          platform: PlatformKind.web,
          isSupported: false,
          message: 'Web 端应使用浏览器 Notification API 的独立适配器。',
        );
      case PlatformKind.unknown:
        return const LocalNotificationSupport(
          platform: PlatformKind.unknown,
          isSupported: false,
          message: '无法识别当前平台，未发送通知。',
        );
    }
  }

  @override
  Stream<LocalNotificationTapEvent> get tapEvents => _tapEvents.stream;

  @override
  Future<void> initialize() async {
    if (_initialized || !support.isSupported) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_notification'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
      macOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
      linux: LinuxInitializationSettings(defaultActionName: '打开'),
      windows: WindowsInitializationSettings(
        appName: 'Goto IM',
        appUserModelId: 'GotoIM.GotoIMFlutter',
        // Keep this stable. Windows uses it to register the toast activation
        // callback for this desktop application.
        guid: 'f65966a8-0ef4-4773-819c-b6e650c70b95',
      ),
    );
    try {
      final initialized = await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
      );
      if (initialized == false) {
        _initializationError = '本地通知插件初始化返回 false。';
        return;
      }
      _initialized = true;
    } catch (error) {
      _initializationError = error.toString();
    }
  }

  @override
  Future<LocalNotificationPermissionResult> requestPermission() async {
    if (!support.isSupported) {
      return LocalNotificationPermissionResult(
        status: LocalNotificationPermissionStatus.unsupported,
        message: support.message,
      );
    }
    await initialize();
    switch (_platformFacade.kind) {
      case PlatformKind.android:
        final granted =
            await _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.requestNotificationsPermission();
        return _androidPermissionResult(granted);
      case PlatformKind.ios:
        final granted = await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
        return _darwinPermissionResult(granted);
      case PlatformKind.macos:
        final granted = await _plugin
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
        return _darwinPermissionResult(granted);
      case PlatformKind.linux:
        return const LocalNotificationPermissionResult(
          status: LocalNotificationPermissionStatus.notRequired,
          message: 'Linux 通知由系统通知服务处理，无应用级运行时授权弹窗。',
        );
      case PlatformKind.windows:
        return const LocalNotificationPermissionResult(
          status: LocalNotificationPermissionStatus.notRequired,
          message: 'Windows Toast 通知无需应用级运行时授权；请在系统通知设置中确认 Goto IM 未被关闭。',
        );
      case PlatformKind.web:
      case PlatformKind.unknown:
        return LocalNotificationPermissionResult(
          status: LocalNotificationPermissionStatus.unsupported,
          message: support.message,
        );
    }
  }

  @override
  Future<LocalNotificationDispatchResult> show(
    LocalNotificationRequest request,
  ) async {
    if (!support.isSupported) {
      return LocalNotificationDispatchResult(
        status: LocalNotificationDispatchStatus.unsupported,
        message: support.message,
      );
    }
    _validateRequest(request);
    await initialize();
    if (request.delay > Duration.zero) {
      _delayedNotifications.remove(request.id)?.cancel();
      _delayedNotifications[request.id] = Timer(request.delay, () {
        _delayedNotifications.remove(request.id);
        unawaited(_showNow(request));
      });
      return LocalNotificationDispatchResult(
        status: LocalNotificationDispatchStatus.queued,
        message:
            '已在当前应用进程中排队，将在 ${request.delay.inSeconds} 秒后展示；关闭或杀死应用会取消该延迟任务。',
      );
    }
    await _showNow(request);
    return const LocalNotificationDispatchResult(
      status: LocalNotificationDispatchStatus.shown,
      message: '已请求系统展示本地通知。',
    );
  }

  @override
  Future<void> cancel(int id) async {
    _delayedNotifications.remove(id)?.cancel();
    if (support.isSupported) await _plugin.cancel(id: id);
  }

  @override
  Future<void> cancelAll() async {
    for (final timer in _delayedNotifications.values) {
      timer.cancel();
    }
    _delayedNotifications.clear();
    if (support.isSupported) await _plugin.cancelAll();
  }

  @override
  Future<void> dispose() async {
    for (final timer in _delayedNotifications.values) {
      timer.cancel();
    }
    _delayedNotifications.clear();
    await _tapEvents.close();
  }

  Future<void> _showNow(LocalNotificationRequest request) => _plugin.show(
    id: request.id,
    title: request.title,
    body: request.body,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        request.channelId,
        request.channelName,
        channelDescription: 'Goto IM 本地通知',
        importance: Importance.max,
        priority: Priority.high,
        ongoing: request.ongoing,
        autoCancel: !request.ongoing,
        actions:
            request.actions
                .map(
                  (action) => AndroidNotificationAction(
                    action.id,
                    action.title,
                    showsUserInterface: action.showsUserInterface,
                    cancelNotification: false,
                  ),
                )
                .toList(),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
      macOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
      linux: const LinuxNotificationDetails(),
      windows: const WindowsNotificationDetails(),
    ),
    payload: request.payload,
  );

  void _onNotificationResponse(NotificationResponse response) {
    if (_tapEvents.isClosed) return;
    _tapEvents.add(
      LocalNotificationTapEvent(
        receivedAt: DateTime.now(),
        payload: response.payload ?? '',
        actionId: response.actionId,
      ),
    );
  }

  LocalNotificationPermissionResult _androidPermissionResult(bool? granted) {
    if (granted == true) {
      return const LocalNotificationPermissionResult(
        status: LocalNotificationPermissionStatus.granted,
        message: 'Android 通知权限已授权。',
      );
    }
    if (granted == false) {
      return const LocalNotificationPermissionResult(
        status: LocalNotificationPermissionStatus.denied,
        message: 'Android 通知权限被拒绝，请在系统设置中开启。',
      );
    }
    return const LocalNotificationPermissionResult(
      status: LocalNotificationPermissionStatus.notRequired,
      message: '当前 Android 版本不需要运行时通知授权，或系统未返回授权状态。',
    );
  }

  LocalNotificationPermissionResult _darwinPermissionResult(bool? granted) {
    if (granted == true) {
      return const LocalNotificationPermissionResult(
        status: LocalNotificationPermissionStatus.granted,
        message: 'Apple 平台通知权限已授权。',
      );
    }
    if (granted == false) {
      return const LocalNotificationPermissionResult(
        status: LocalNotificationPermissionStatus.denied,
        message: 'Apple 平台通知权限被拒绝，请在系统设置中开启。',
      );
    }
    return const LocalNotificationPermissionResult(
      status: LocalNotificationPermissionStatus.unknown,
      message: '系统未返回明确的通知授权状态。',
    );
  }

  void _validateRequest(LocalNotificationRequest request) {
    if (request.id < 0) {
      throw ArgumentError.value(request.id, 'id', '通知 ID 必须是非负整数。');
    }
    if (request.channelId.trim().isEmpty) {
      throw ArgumentError.value(
        request.channelId,
        'channelId',
        'Android 渠道 ID 不能为空。',
      );
    }
    if (request.channelName.trim().isEmpty) {
      throw ArgumentError.value(
        request.channelName,
        'channelName',
        'Android 渠道名称不能为空。',
      );
    }
    if (request.delay.isNegative) {
      throw ArgumentError.value(request.delay, 'delay', '延迟时间不能小于 0。');
    }
  }
}
