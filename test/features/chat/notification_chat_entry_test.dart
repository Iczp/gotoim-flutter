import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/notifications/local_notification_contract.dart';
import 'package:gotoim_flutter/core/services/window_service.dart';
import 'package:gotoim_flutter/features/session/application/active_chat_registry.dart';
import 'package:gotoim_flutter/features/session/application/message_alert_coordinator.dart';
import 'package:gotoim_flutter/features/session/application/message_alert_settings.dart';

class _Notifications implements LocalNotificationService {
  final taps = StreamController<LocalNotificationTapEvent>.broadcast(
    sync: true,
  );
  @override
  Stream<LocalNotificationTapEvent> get tapEvents => taps.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Windows implements WindowService {
  final opened = <String>[];
  @override
  Future<void> openChat({
    required String sessionUnitId,
    int? ownerId,
    String? title,
  }) async {
    opened.add('$ownerId:$sessionUnitId:$title');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'notification uses unified window entry without a page context',
    () async {
      final notifications = _Notifications();
      final windows = _Windows();
      final active = ActiveChatRegistry();
      final settings = MessageAlertSettings();
      final coordinator = MessageAlertCoordinator(
        activeChat: active,
        settings: settings,
        notifications: notifications,
        windowService: windows,
      );
      notifications.taps.add(
        LocalNotificationTapEvent(
          receivedAt: DateTime.now(),
          payload: jsonEncode({
            'type': 'chat-message',
            'sessionUnitId': 'session',
            'ownerId': 42,
            'title': '中文聊天',
          }),
        ),
      );
      expect(windows.opened, ['42:session:中文聊天']);
      notifications.taps.add(
        LocalNotificationTapEvent(
          receivedAt: DateTime.now(),
          payload: '{invalid',
        ),
      );
      notifications.taps.add(
        LocalNotificationTapEvent(
          receivedAt: DateTime.now(),
          payload: jsonEncode({
            'type': 'chat-message',
            'sessionUnitId': '',
            'ownerId': 0,
          }),
        ),
      );
      expect(windows.opened, hasLength(1));
      await coordinator.dispose();
      await notifications.taps.close();
      active.dispose();
      settings.dispose();
    },
  );
}
