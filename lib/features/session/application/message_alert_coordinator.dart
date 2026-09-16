import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_navigation.dart';
import '../../../app/application_providers.dart';
import '../../../core/native/native.dart';
import '../../../core/notifications/local_notification_contract.dart';
import '../../chat/data/models/chat_message.dart';
import '../data/models/session_summary.dart';
import 'active_chat_registry.dart';
import 'message_alert_settings.dart';

/// Decides user-visible feedback only after an incoming message is durable.
/// SignalR is transport; this class is the single notification policy point.
class MessageAlertCoordinator {
  MessageAlertCoordinator({
    required ActiveChatRegistry activeChat,
    required MessageAlertSettings settings,
    required LocalNotificationService notifications,
  }) : _activeChat = activeChat,
       _settings = settings,
       _notifications = notifications {
    _tapSubscription = _notifications.tapEvents.listen(_openNotificationTarget);
  }

  final ActiveChatRegistry _activeChat;
  final MessageAlertSettings _settings;
  final LocalNotificationService _notifications;
  late final StreamSubscription<LocalNotificationTapEvent> _tapSubscription;
  OverlayEntry? _foregroundBanner;
  Timer? _foregroundBannerTimer;

  static const _foregroundVibrationDuration = 160;

  Future<void> handleIncoming({
    required ChatMessage message,
    required SessionSummary? session,
  }) async {
    if (message.isMine ||
        session?.isImmersed == true ||
        session?.isMuted == true) {
      return;
    }
    final settings = await _settings.forSession(message.sessionUnitId);
    final activeChat = _activeChat.isForegroundSession(message.sessionUnitId);
    if (activeChat) {
      if (settings.vibrationEnabled && settings.activeChatVibrationEnabled) {
        await Native.vibrate(
          HapticFeedbackType.medium,
          _foregroundVibrationDuration,
        );
      }
      return;
    }

    if (_activeChat.isForeground) {
      if (settings.vibrationEnabled) {
        await Native.vibrate(
          HapticFeedbackType.medium,
          _foregroundVibrationDuration,
        );
      }
      _showForegroundBanner(message, session, settings);
      return;
    }

    if (!settings.notificationsEnabled) return;
    final title = session?.title ?? message.senderName;
    final body = settings.previewEnabled ? _preview(message) : '你收到一条新消息';
    await _notifications.show(
      LocalNotificationRequest(
        id: message.serverId ?? message.localId.hashCode.abs(),
        channelId:
            settings.soundEnabled || settings.vibrationEnabled
                ? 'chat_messages_alert'
                : 'chat_messages_silent',
        channelName: '聊天消息',
        title: title,
        body: body,
        playSound: settings.soundEnabled,
        enableVibration: settings.vibrationEnabled,
        payload: jsonEncode(<String, Object?>{
          'type': 'chat-message',
          'sessionUnitId': message.sessionUnitId,
          'ownerId': message.ownerId,
          'title': title,
        }),
      ),
    );
  }

  void _showForegroundBanner(
    ChatMessage message,
    SessionSummary? session,
    SessionMessageAlertSettings settings,
  ) {
    if (!settings.notificationsEnabled) return;
    final context = rootNavigatorKey.currentContext;
    final overlay = rootNavigatorKey.currentState?.overlay;
    if (context == null || overlay == null) return;
    final title = session?.title ?? message.senderName;
    final body = settings.previewEnabled ? _preview(message) : '你收到一条新消息';
    _dismissForegroundBanner();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder:
          (context) => Positioned(
            top: 8,
            left: 12,
            right: 12,
            child: Material(
              color: Colors.transparent,
              child: SafeArea(
                bottom: false,
                child: Card(
                  margin: EdgeInsets.zero,
                  elevation: 8,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      _dismissForegroundBanner();
                      _openChat(message.sessionUnitId, message.ownerId, title);
                    },
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.chat_bubble_outline_rounded),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  body,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              _dismissForegroundBanner();
                              _openChat(
                                message.sessionUnitId,
                                message.ownerId,
                                title,
                              );
                            },
                            child: const Text('查看'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
    );
    _foregroundBanner = entry;
    overlay.insert(entry);
    _foregroundBannerTimer = Timer(
      const Duration(seconds: 4),
      _dismissForegroundBanner,
    );
  }

  void _dismissForegroundBanner() {
    _foregroundBannerTimer?.cancel();
    _foregroundBannerTimer = null;
    _foregroundBanner?.remove();
    _foregroundBanner = null;
  }

  String _preview(ChatMessage message) =>
      message.text.trim().isEmpty
          ? '[${message.messageType}]'
          : message.text.trim();

  void _openNotificationTarget(LocalNotificationTapEvent event) {
    try {
      final data = jsonDecode(event.payload);
      if (data is! Map || data['type'] != 'chat-message') return;
      _openChat(
        '${data['sessionUnitId'] ?? ''}',
        int.tryParse('${data['ownerId'] ?? ''}') ?? 0,
        '${data['title'] ?? '聊天'}',
      );
    } catch (_) {}
  }

  void _openChat(String sessionUnitId, int ownerId, String title) {
    if (sessionUnitId.isEmpty || ownerId <= 0) return;
    final context = rootNavigatorKey.currentContext;
    if (context?.mounted != true) return;
    GoRouter.of(context!).push(
      '/chat/${Uri.encodeComponent(sessionUnitId)}?ownerId=$ownerId&title=${Uri.encodeQueryComponent(title)}',
    );
  }

  Future<void> dispose() async {
    _dismissForegroundBanner();
    await _tapSubscription.cancel();
  }
}

final messageAlertCoordinatorProvider = Provider<MessageAlertCoordinator>((
  ref,
) {
  final coordinator = MessageAlertCoordinator(
    activeChat: ref.watch(activeChatRegistryProvider),
    settings: ref.watch(messageAlertSettingsProvider),
    notifications: ref.watch(localNotificationServiceProvider),
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});
