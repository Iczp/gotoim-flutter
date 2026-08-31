import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../local_file_server.dart';
import '../local_file_server_controller.dart';

class TerminalDetailsPage extends ConsumerStatefulWidget {
  const TerminalDetailsPage({required this.terminalId, super.key});
  final String terminalId;

  @override
  ConsumerState<TerminalDetailsPage> createState() =>
      _TerminalDetailsPageState();
}

class _TerminalDetailsPageState extends ConsumerState<TerminalDetailsPage> {
  late final LocalFileServerService _service;

  @override
  void initState() {
    super.initState();
    _service = ref.read(localFileServerProvider)..addListener(_refresh);
  }

  @override
  void dispose() {
    _service.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final terminal = _service.terminalFor(widget.terminalId);
    if (terminal == null) {
      return const Scaffold(body: Center(child: Text('终端记录不存在或文件共享已关闭。')));
    }
    final online = terminal.status != TerminalStatus.offline;
    final activities = _service.activitiesFor(widget.terminalId);
    return Scaffold(
      appBar: AppBar(title: const Text('终端操作日志')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    terminal.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text('状态：${online ? '在线 · ${terminal.status.name}' : '已断开'}'),
                  Text('平台：${terminal.platform} · ${terminal.ip}'),
                  Text('连接时间：${terminal.connectedAt.toLocal()}'),
                  Text('最后活动：${terminal.lastActiveAt.toLocal()}'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed:
                        online
                            ? () => _service.disconnectTerminal(terminal.id)
                            : null,
                    icon: const Icon(Icons.link_off_outlined),
                    label: const Text('断开连接'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '实时操作日志（最多保留 200 条）',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (activities.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('暂未记录到操作。'),
              ),
            ),
          ...activities.map(
            (activity) => Card(
              child: ListTile(
                leading: const Icon(Icons.history_outlined),
                title: Text(activity.description),
                subtitle: Text(
                  '${activity.action} · ${activity.occurredAt.toLocal()}',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
