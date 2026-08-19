import '../platform/platform_facade.dart';
import 'local_notification_contract.dart';

LocalNotificationService createLocalNotificationService({
  required PlatformFacade platformFacade,
}) => _UnsupportedLocalNotificationService(platformFacade);

class _UnsupportedLocalNotificationService implements LocalNotificationService {
  _UnsupportedLocalNotificationService(this._platformFacade);

  final PlatformFacade _platformFacade;

  @override
  LocalNotificationSupport get support => LocalNotificationSupport(
    platform: _platformFacade.kind,
    isSupported: false,
    message:
        _platformFacade.isWeb
            ? 'Web 端不使用本地通知插件；后续应通过浏览器 Notification API 单独实现。'
            : '当前平台尚未接入本地通知实现。',
  );

  @override
  Stream<LocalNotificationTapEvent> get tapEvents =>
      const Stream<LocalNotificationTapEvent>.empty();

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<LocalNotificationPermissionResult> requestPermission() async =>
      LocalNotificationPermissionResult(
        status: LocalNotificationPermissionStatus.unsupported,
        message: support.message,
      );

  @override
  Future<LocalNotificationDispatchResult> show(
    LocalNotificationRequest request,
  ) async => LocalNotificationDispatchResult(
    status: LocalNotificationDispatchStatus.unsupported,
    message: support.message,
  );
}
