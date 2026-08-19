import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/local_notification_service.dart';
import '../../../core/services/clipboard_service.dart';
import '../application/local_notification_diagnostics_controller.dart';

class LocalNotificationDiagnosticsPage extends ConsumerStatefulWidget {
  const LocalNotificationDiagnosticsPage({super.key});

  @override
  ConsumerState<LocalNotificationDiagnosticsPage> createState() =>
      _LocalNotificationDiagnosticsPageState();
}

class _LocalNotificationDiagnosticsPageState
    extends ConsumerState<LocalNotificationDiagnosticsPage> {
  final _idController = TextEditingController(text: '1001');
  final _channelIdController = TextEditingController(text: 'gotoim_debug');
  final _channelNameController = TextEditingController(text: 'Goto IM 调试通知');
  final _titleController = TextEditingController(text: 'Goto IM 测试通知');
  final _bodyController = TextEditingController(text: '这是来自 Flutter 的本地通知。');
  final _payloadController = TextEditingController(
    text: '{"type":"debug","route":"/diagnostics/notifications"}',
  );
  final _delayController = TextEditingController(text: '0');

  @override
  void dispose() {
    _idController.dispose();
    _channelIdController.dispose();
    _channelNameController.dispose();
    _titleController.dispose();
    _bodyController.dispose();
    _payloadController.dispose();
    _delayController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(body: Center(child: Text('开发诊断仅在 Debug 模式可用。')));
    }
    final controller = ref.watch(
      localNotificationDiagnosticsControllerProvider,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('本地通知测试'),
        actions: [
          IconButton(
            tooltip: '清空点击事件',
            onPressed: controller.clearTapEvents,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _InfoCard(
            title: '当前平台能力',
            detail:
                'platform: ${controller.support.platform.name}\n支持: ${controller.support.isSupported}\n${controller.support.message}',
          ),
          const SizedBox(height: 16),
          _ActionCard(
            title: '1. 请求通知权限',
            description: 'Android 13+、iOS、macOS 会在此请求系统授权；Linux 通常无需应用级授权。',
            status: controller.permissionStatus,
            onPressed:
                controller.permissionStatus ==
                        LocalNotificationTestStatus.working
                    ? null
                    : controller.requestPermission,
            buttonText: '请求权限',
            detail: controller.permissionResult,
          ),
          const SizedBox(height: 16),
          Text('2. 通知参数', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _field(
            _idController,
            '通知 ID',
            helperText: '相同 ID 会更新/覆盖同一通知；必须是非负整数',
            keyboardType: TextInputType.number,
          ),
          _field(
            _channelIdController,
            'Android 渠道 ID',
            helperText: 'Android 8+ 用于分类；创建后关键系统设置不可更改',
          ),
          _field(
            _channelNameController,
            'Android 渠道名称',
            helperText: '用户在 Android 设置中可见的渠道名称',
          ),
          _field(_titleController, '标题'),
          _field(_bodyController, '正文', maxLines: 3),
          _field(
            _payloadController,
            'Payload',
            helperText: '点击通知后原样回传；建议放 JSON 路由数据，不放 Token',
            maxLines: 3,
          ),
          _field(
            _delayController,
            '延迟秒数',
            helperText: '0 为立即展示；大于 0 仅在应用进程存活时有效',
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 8),
          _ActionCard(
            title: '3. 发送本地通知',
            description: '使用上方可编辑参数。测试时请切到后台或锁屏，以便观察系统横幅。',
            status: controller.dispatchStatus,
            onPressed:
                controller.dispatchStatus == LocalNotificationTestStatus.working
                    ? null
                    : _showNotification,
            buttonText: '发送通知',
            detail: controller.dispatchResult,
          ),
          const SizedBox(height: 16),
          _ActionCard(
            title: '4. 取消通知',
            description: '按当前通知 ID 取消，或取消全部通知。',
            status: controller.cancelStatus,
            onPressed:
                controller.cancelStatus == LocalNotificationTestStatus.working
                    ? null
                    : _cancelCurrent,
            buttonText: '取消当前 ID',
            detail: controller.cancelResult,
            extraAction: OutlinedButton(
              onPressed:
                  controller.cancelStatus == LocalNotificationTestStatus.working
                      ? null
                      : controller.cancelAll,
              child: const Text('取消全部'),
            ),
          ),
          if (controller.error != null) ...[
            const SizedBox(height: 8),
            SelectableText(
              controller.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            '通知点击事件（最多保留 100 条）',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (controller.tapEvents.isEmpty)
            const Text('暂未收到通知点击事件。')
          else
            ...controller.tapEvents.map(
              (event) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(event.receivedAt.toIso8601String()),
                      Text('actionId: ${event.actionId ?? 'default'}'),
                      const SizedBox(height: 8),
                      SelectableText(event.payload),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => _copy(event.payload),
                          icon: const Icon(Icons.copy_outlined),
                          label: const Text('复制 Payload'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? helperText,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      minLines: 1,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: '复制',
          icon: const Icon(Icons.copy_outlined),
          onPressed: () => _copy(controller.text),
        ),
      ),
    ),
  );

  void _showNotification() {
    final request = _buildRequest();
    if (request == null) return;
    ref.read(localNotificationDiagnosticsControllerProvider).show(request);
  }

  void _cancelCurrent() {
    final id = int.tryParse(_idController.text.trim());
    if (id == null || id < 0) {
      _showInputError('通知 ID 必须是非负整数。');
      return;
    }
    ref.read(localNotificationDiagnosticsControllerProvider).cancel(id);
  }

  LocalNotificationRequest? _buildRequest() {
    final id = int.tryParse(_idController.text.trim());
    final delay = int.tryParse(_delayController.text.trim());
    if (id == null || id < 0) {
      _showInputError('通知 ID 必须是非负整数。');
      return null;
    }
    if (delay == null || delay < 0) {
      _showInputError('延迟秒数必须是非负整数。');
      return null;
    }
    return LocalNotificationRequest(
      id: id,
      channelId: _channelIdController.text.trim(),
      channelName: _channelNameController.text.trim(),
      title: _titleController.text,
      body: _bodyController.text,
      payload: _payloadController.text,
      delay: Duration(seconds: delay),
    );
  }

  Future<void> _copy(String value) async {
    await ref.read(clipboardServiceProvider).copy(value);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已复制。')));
    }
  }

  void _showInputError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SelectableText(detail),
        ],
      ),
    ),
  );
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.title,
    required this.description,
    required this.status,
    required this.onPressed,
    required this.buttonText,
    this.detail,
    this.extraAction,
  });

  final String title;
  final String description;
  final LocalNotificationTestStatus status;
  final VoidCallback? onPressed;
  final String buttonText;
  final String? detail;
  final Widget? extraAction;

  @override
  Widget build(BuildContext context) {
    final isFailure = status == LocalNotificationTestStatus.failure;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(description),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: onPressed,
                  child:
                      status == LocalNotificationTestStatus.working
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : Text(buttonText),
                ),
                if (extraAction != null) extraAction!,
              ],
            ),
            if (detail != null) ...[
              const SizedBox(height: 12),
              SelectableText(
                detail!,
                style: TextStyle(
                  color: isFailure ? Theme.of(context).colorScheme.error : null,
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
