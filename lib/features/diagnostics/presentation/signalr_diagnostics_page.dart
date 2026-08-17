import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/clipboard_service.dart';
import '../application/connection_test_controller.dart';

class SignalRDiagnosticsPage extends ConsumerWidget {
  const SignalRDiagnosticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kDebugMode) {
      return const Scaffold(body: Center(child: Text('开发诊断仅在 Debug 模式可用。')));
    }
    final controller = ref.watch(connectionTestControllerProvider);
    final info = controller.signalRConnectionInfo;
    return Scaffold(
      appBar: AppBar(
        title: const Text('SignalR 诊断'),
        actions: [
          IconButton(
            tooltip: '清空事件',
            onPressed: controller.clearSignalREvents,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('连接控制', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: controller.connectSignalR,
                child: const Text('连接'),
              ),
              OutlinedButton(
                onPressed: controller.disconnectSignalR,
                child: const Text('断开'),
              ),
              OutlinedButton(
                onPressed: controller.reconnectSignalR,
                child: const Text('重新连接'),
              ),
            ],
          ),
          if (controller.signalRError != null) ...[
            const SizedBox(height: 8),
            SelectableText(
              controller.signalRError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          Text('连接详情', style: Theme.of(context).textTheme.titleMedium),
          _ValueRow(label: '状态', value: info.state.name),
          _ValueRow(label: 'Hub URL（含设备参数）', value: info.hubUrl),
          _ValueRow(label: 'connectionId', value: info.connectionId ?? ''),
          _ValueRow(
            label: '客户端 keep-alive 配置',
            value: '${info.keepAliveInterval.inSeconds} 秒',
          ),
          _ValueRow(
            label: '服务端超时配置',
            value: '${info.serverTimeout.inSeconds} 秒',
          ),
          _ValueRow(
            label: '最后收到业务事件',
            value: info.lastReceivedAt?.toIso8601String() ?? '暂无',
          ),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
                'keep-alive 为 SignalR 客户端库的发送配置；库未公开每个 Ping 的回调，最后收到业务事件不等同于心跳。'),
          ),
          const SizedBox(height: 20),
          Text('接收事件（最多保留 100 条）',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (controller.signalREvents.isEmpty)
            const Text('暂无接收事件。')
          else
            ...controller.signalREvents.map(
              (event) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(event.title,
                          style: Theme.of(context).textTheme.titleSmall),
                      Text(event.receivedAt.toIso8601String()),
                      const SizedBox(height: 8),
                      SelectableText(event.details),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () async {
                            await ref
                                .read(clipboardServiceProvider)
                                .copy(event.details);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('事件 payload 已复制。')),
                              );
                            }
                          },
                          icon: const Icon(Icons.copy_outlined),
                          label: const Text('复制 payload'),
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
}

class _ValueRow extends ConsumerWidget {
  const _ValueRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: TextField(
          controller: TextEditingController(text: value),
          readOnly: true,
          minLines: 1,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: '复制',
              icon: const Icon(Icons.copy_outlined),
              onPressed: value.isEmpty
                  ? null
                  : () => ref.read(clipboardServiceProvider).copy(value),
            ),
          ),
        ),
      );
}
