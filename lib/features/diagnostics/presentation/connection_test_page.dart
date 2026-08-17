import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/realtime/signalr_gateway.dart';
import '../application/connection_test_controller.dart';

class ConnectionTestPage extends ConsumerWidget {
  const ConnectionTestPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(connectionTestControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('连接测试')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _TestCard(
            title: '认证 API',
            description: '使用当前 Token 调用 /connect/userinfo',
            status: controller.apiStatus,
            onPressed: controller.apiStatus == ConnectionTestStatus.testing
                ? null
                : controller.testAuthenticatedApi,
            buttonText: '测试 API',
            detail: controller.apiError ?? controller.apiResult,
          ),
          const SizedBox(height: 16),
          _TestCard(
            title: 'SignalR Chat Hub',
            description: '连接状态：${_connectionLabel(controller.connectionState)}',
            status: controller.signalRStatus,
            onPressed: controller.signalRStatus == ConnectionTestStatus.testing
                ? null
                : controller.reconnectSignalR,
            buttonText: '重新连接',
            detail: controller.signalRError ?? controller.latestEvent,
          ),
          const SizedBox(height: 12),
          const Text(
            '该页面不会显示 access token、client secret 或聊天消息内容。',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _connectionLabel(SignalRConnectionState state) {
    switch (state) {
      case SignalRConnectionState.disconnected:
        return '未连接';
      case SignalRConnectionState.connecting:
        return '连接中';
      case SignalRConnectionState.connected:
        return '已连接';
      case SignalRConnectionState.reconnecting:
        return '重连中';
      case SignalRConnectionState.disconnecting:
        return '断开中';
    }
  }
}

class _TestCard extends StatelessWidget {
  const _TestCard({
    required this.title,
    required this.description,
    required this.status,
    required this.onPressed,
    required this.buttonText,
    this.detail,
  });

  final String title;
  final String description;
  final ConnectionTestStatus status;
  final VoidCallback? onPressed;
  final String buttonText;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFailure = status == ConnectionTestStatus.failure;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(description),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: onPressed,
              child: status == ConnectionTestStatus.testing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(buttonText),
            ),
            if (detail != null) ...[
              const SizedBox(height: 12),
              SelectableText(
                detail!,
                style: TextStyle(
                  color: isFailure ? theme.colorScheme.error : null,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
