import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/application_providers.dart';
import '../../../core/notifications/local_notification_contract.dart';
import '../../../core/widgets/cell_group.dart';
import '../../session/application/message_alert_settings.dart';

class MessageAlertSettingsPage extends ConsumerStatefulWidget {
  const MessageAlertSettingsPage({required this.sessionUnitId, required this.title, super.key});
  final String sessionUnitId;
  final String title;

  @override
  ConsumerState<MessageAlertSettingsPage> createState() => _MessageAlertSettingsPageState();
}

class _MessageAlertSettingsPageState extends ConsumerState<MessageAlertSettingsPage> {
  late final MessageAlertSettings _settings;
  SessionMessageAlertSettings? _session;
  LocalNotificationPermissionResult? _permission;

  @override
  void initState() {
    super.initState();
    _settings = ref.read(messageAlertSettingsProvider);
    _settings.addListener(_onSettingsChanged);
    _permission = null;
    _loadSession();
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSession() async {
    final session = await _settings.forSession(widget.sessionUnitId);
    if (mounted) setState(() => _session = session);
  }

  Future<void> _update({bool? notificationsEnabled, bool? vibrationEnabled, bool? soundEnabled, bool? activeChatVibrationEnabled, bool? previewEnabled}) async {
    await _settings.updateSession(widget.sessionUnitId,
      notificationsEnabled: notificationsEnabled, vibrationEnabled: vibrationEnabled,
      soundEnabled: soundEnabled, activeChatVibrationEnabled: activeChatVibrationEnabled, previewEnabled: previewEnabled);
    await _loadSession();
  }

  Future<void> _requestPermission() async {
    final result = await ref.read(localNotificationServiceProvider).requestPermission();
    if (mounted) setState(() => _permission = result);
  }

  @override
  Widget build(BuildContext context) {
    final support = ref.read(localNotificationServiceProvider).support;
    final session = _session;
    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final enabled = session.notificationsEnabled;
    return Scaffold(
      appBar: AppBar(title: Text('${widget.title} · 消息提醒')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          CellGroup(title: '提醒方式', children: [
            SwitchListTile(
              secondary: const Icon(Icons.notifications_active_outlined),
              title: const Text('新消息通知'),
              subtitle: const Text('后台仍在线时显示系统通知；会话免打扰优先'),
              value: enabled,
              onChanged: (value) => _update(notificationsEnabled: value),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.volume_up_outlined),
              title: const Text('通知声音'),
              value: session.soundEnabled,
              onChanged: enabled ? (value) => _update(soundEnabled: value) : null,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.vibration_outlined),
              title: const Text('振动'),
              value: session.vibrationEnabled,
              onChanged: enabled ? (value) => _update(vibrationEnabled: value) : null,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.preview_outlined),
              title: const Text('显示消息预览'),
              subtitle: const Text('关闭后通知仅显示“你收到一条新消息”'),
              value: session.previewEnabled,
              onChanged: enabled ? (value) => _update(previewEnabled: value) : null,
            ),
          ]),
          CellGroup(title: '正在聊天', children: [
            SwitchListTile(
              secondary: const Icon(Icons.chat_bubble_outline),
              title: const Text('当前聊天页振动'),
              subtitle: const Text('正在查看该会话时不弹通知、不播放声音，仅短振动'),
              value: session.activeChatVibrationEnabled,
              onChanged: session.vibrationEnabled
                  ? (value) => _update(activeChatVibrationEnabled: value)
                  : null,
            ),
          ]),
          CellGroup(title: '系统通知权限', children: [
            ListTile(
              leading: Icon(support.isSupported ? Icons.verified_user_outlined : Icons.phonelink_erase_outlined),
              title: Text(support.isSupported ? '授权系统通知' : '当前平台不支持本地通知'),
              subtitle: Text(_permission?.message ?? support.message),
              trailing: support.isSupported ? FilledButton(onPressed: _requestPermission, child: const Text('检查/授权')) : null,
            ),
          ]),
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 24),
            child: Text('应用被系统杀死或 SignalR 离线时，需要服务端 Push（FCM/APNs/HMS）才能提醒；本地通知不能替代远程 Push。'),
          ),
        ],
      ),
    );
  }
}
