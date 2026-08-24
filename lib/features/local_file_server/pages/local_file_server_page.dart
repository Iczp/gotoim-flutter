import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/services/clipboard_service.dart';
import '../local_file_server.dart';
import '../local_file_server_controller.dart';

class LocalFileServerPage extends ConsumerStatefulWidget {
  const LocalFileServerPage({super.key});

  @override
  ConsumerState<LocalFileServerPage> createState() =>
      _LocalFileServerPageState();
}

class _LocalFileServerPageState extends ConsumerState<LocalFileServerPage> {
  late final LocalFileServerService _service;

  @override
  void initState() {
    super.initState();
    _service = ref.read(localFileServerProvider)
      ..addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    final state = service.state;
    final running = state.status == LocalFileServerStatus.running;
    return Scaffold(
      appBar: AppBar(title: const Text('局域网文件管理')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        running
                            ? Icons.check_circle
                            : Icons.pause_circle_outline,
                        color:
                            running
                                ? Colors.green
                                : Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _statusText(state.status),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  if (state.error != null) ...[
                    const SizedBox(height: 12),
                    SelectableText(
                      state.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  if (running) ...[
                    const SizedBox(height: 16),
                    _CopyField(label: '访问地址', value: state.address!),
                    const SizedBox(height: 12),
                    _CopyField(label: '验证码', value: state.verificationCode!),
                    const SizedBox(height: 16),
                    Center(
                      child: QrImageView(data: state.qrLoginUrl!, size: 180),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '二维码仅可使用一次，5 分钟内有效；输入验证码也可进入。',
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed:
                        state.status == LocalFileServerStatus.starting
                            ? null
                            : (running ? service.stop : service.start),
                    icon: Icon(
                      running
                          ? Icons.stop_circle_outlined
                          : Icons.play_arrow_outlined,
                    ),
                    label: Text(running ? '关闭文件共享' : '开启文件共享'),
                  ),
                  if (Theme.of(context).platform == TargetPlatform.iOS) ...[
                    const SizedBox(height: 12),
                    const Text('iOS 在后台或锁屏时可能暂停服务；传输期间请保持 App 在前台。'),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '已连接终端 ${state.terminals.length}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (state.terminals.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('暂无已连接终端。'),
              ),
            ),
          ...state.terminals.map(
            (terminal) => Card(
              child: ListTile(
                leading: const Icon(Icons.devices_outlined),
                title: Text(terminal.name),
                subtitle: Text(
                  '${terminal.platform} · ${terminal.ip}\n${_terminalState(terminal)}',
                ),
                isThreeLine: true,
                trailing: TextButton(
                  onPressed: () => service.disconnectTerminal(terminal.id),
                  child: const Text('断开'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _statusText(LocalFileServerStatus status) {
    switch (status) {
      case LocalFileServerStatus.running:
        return '服务已开启';
      case LocalFileServerStatus.starting:
        return '服务启动中';
      case LocalFileServerStatus.failed:
        return '服务启动失败';
      case LocalFileServerStatus.unsupported:
        return '当前平台暂不支持';
      case LocalFileServerStatus.stopped:
        return '服务未开启';
    }
  }

  String _terminalState(ConnectedTerminal terminal) {
    final current = terminal.transferLabel;
    if (current != null &&
        terminal.totalBytes != null &&
        terminal.receivedBytes != null) {
      return '$current ${(terminal.receivedBytes! * 100 / terminal.totalBytes!).toStringAsFixed(0)}%';
    }
    return terminal.status == TerminalStatus.idle
        ? '在线 · 空闲'
        : terminal.status.name;
  }
}

class _CopyField extends ConsumerWidget {
  const _CopyField({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context, WidgetRef ref) => TextField(
    controller: TextEditingController(text: value),
    readOnly: true,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      suffixIcon: IconButton(
        tooltip: '复制',
        icon: const Icon(Icons.copy_outlined),
        onPressed: () async {
          await ref.read(clipboardServiceProvider).copy(value);
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('已复制。')));
          }
        },
      ),
    ),
  );
}
