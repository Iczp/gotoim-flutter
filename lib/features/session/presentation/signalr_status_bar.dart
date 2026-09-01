import 'package:flutter/material.dart';

import '../application/session_list_controller.dart';

/// Status banner showing SignalR connection status and reconnect action.
class SignalRStatusBar extends StatelessWidget {
  const SignalRStatusBar({
    required this.state,
    required this.onReconnect,
    super.key,
  });

  final SessionRealtimeStatus state;
  final Future<void> Function() onReconnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final busy =
        state == SessionRealtimeStatus.connecting ||
        state == SessionRealtimeStatus.reconnecting;
    final text = switch (state) {
      SessionRealtimeStatus.connecting => 'SignalR 正在连接…',
      SessionRealtimeStatus.reconnecting => 'SignalR 正在重新连接…',
      SessionRealtimeStatus.disconnecting => 'SignalR 正在断开…',
      SessionRealtimeStatus.disconnected => 'SignalR 已断开',
      SessionRealtimeStatus.connected => '',
    };

    return Material(
      color: colorScheme.errorContainer,
      child: InkWell(
        onTap: busy ? null : onReconnect,
        child: SizedBox(
          height: 38,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  Icons.cloud_off_outlined,
                  size: 18,
                  color: colorScheme.onErrorContainer,
                ),
              const SizedBox(width: 8),
              Text(
                text,
                style: TextStyle(
                  color: colorScheme.onErrorContainer,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (!busy)
                Text(
                  '，点击重连',
                  style: TextStyle(
                    color: colorScheme.onErrorContainer,
                    fontSize: 13,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
