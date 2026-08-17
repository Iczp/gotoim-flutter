import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/connection_test_controller.dart';

class ConnectionTestPage extends ConsumerStatefulWidget {
  const ConnectionTestPage({super.key});

  @override
  ConsumerState<ConnectionTestPage> createState() => _ConnectionTestPageState();
}

class _ConnectionTestPageState extends ConsumerState<ConnectionTestPage> {
  final _ownerIdController = TextEditingController();
  final _sessionUnitIdController = TextEditingController();

  @override
  void dispose() {
    _ownerIdController.dispose();
    _sessionUnitIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(connectionTestControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('连接测试')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _TestCard(
            title: '刷新 Token',
            description: '调用 /connect/token，grant_type=refresh_token',
            status: controller.refreshStatus,
            onPressed: controller.refreshStatus == ConnectionTestStatus.testing
                ? null
                : controller.refreshToken,
            buttonText: '刷新 Token',
            detail: controller.refreshError ?? controller.refreshResult,
          ),
          const SizedBox(height: 16),
          _TestCard(
            title: '认证 API',
            description: '使用当前 Token 调用 /connect/userinfo',
            status: controller.apiStatus,
            onPressed: controller.apiStatus == ConnectionTestStatus.testing
                ? null
                : controller.testAuthenticatedApi,
            buttonText: '测试认证 API',
            detail: controller.apiError ?? controller.apiResult,
          ),
          const SizedBox(height: 16),
          _TestCard(
            title: '好友业务 API',
            description:
                'GET /api/chat/session-unit-cache/friends?ownerId=<值>&maxResultCount=100',
            status: controller.friendsStatus,
            onPressed: controller.friendsStatus == ConnectionTestStatus.testing
                ? null
                : () =>
                    controller.testFriendsApi(_ownerIdController.text.trim()),
            buttonText: '测试好友 API',
            detail: controller.friendsError ?? controller.friendsResult,
            input: TextField(
              controller: _ownerIdController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'ownerId',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _TestCard(
            title: '消息业务 API',
            description: 'GET /api/chat/message/fast，需要 sessionUnitId',
            status: controller.messagesStatus,
            onPressed: controller.messagesStatus == ConnectionTestStatus.testing
                ? null
                : () => controller.testMessagesApi(
                      _sessionUnitIdController.text.trim(),
                    ),
            buttonText: '测试消息 API',
            detail: controller.messagesError ?? controller.messagesResult,
            input: TextField(
              controller: _sessionUnitIdController,
              decoration: const InputDecoration(
                labelText: 'sessionUnitId',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '接口返回仅显示摘要；SignalR 详情和 payload 请在独立的 SignalR 测试页查看。',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
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
    this.input,
  });

  final String title;
  final String description;
  final ConnectionTestStatus status;
  final VoidCallback? onPressed;
  final String buttonText;
  final String? detail;
  final Widget? input;

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
            if (input != null) ...[const SizedBox(height: 12), input!],
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
