import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/application_providers.dart';
import '../../../core/logging/app_logger.dart';

class RemoteDevToolsDiagnosticsPage extends ConsumerStatefulWidget {
  const RemoteDevToolsDiagnosticsPage({super.key});

  @override
  ConsumerState<RemoteDevToolsDiagnosticsPage> createState() =>
      _RemoteDevToolsDiagnosticsPageState();
}

class _RemoteDevToolsDiagnosticsPageState
    extends ConsumerState<RemoteDevToolsDiagnosticsPage> {
  Timer? _timer;
  String? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _result = '启动中…';
    });
    try {
      await ref.read(remoteDevServerProvider).start();
      final server = ref.read(remoteDevServerProvider);
      setState(() => _result = server.isRunning
          ? '服务已启动。请使用下方局域网地址访问。'
          : '当前平台或构建模式不支持 Remote DevTools。');
    } catch (error) {
      setState(() => _error = '$error');
    }
  }

  Future<void> _stop() async {
    try {
      await ref.read(remoteDevServerProvider).stop();
      setState(() => _result = '服务已停止。');
    } catch (error) {
      setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final server = ref.watch(remoteDevServerProvider);
    final address = server.url ?? '尚未启动';
    return Scaffold(
      appBar: AppBar(title: const Text('Remote DevTools / AI 日志')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
              '仅 Debug 开发环境可用。日志会在真机内存中保留最近 5000 条，HTTP Header、Token、Cookie、密码等内容会脱敏后才可查看或导出。'),
          const SizedBox(height: 16),
          _Info(label: '状态', value: server.isRunning ? 'Running' : 'Stopped'),
          _Info(label: '访问地址', value: address),
          _Info(label: 'Port', value: '${server.port}'),
          _Info(label: 'WebSocket Clients', value: '${server.clientCount}'),
          _Info(
              label: '日志数量',
              value: '${AppLogger.instance.store.length} / 5000'),
          _Info(
              label: 'Capture',
              value: AppLogger.instance.captureEnabled ? '采集中' : '已停止'),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
                onPressed: kDebugMode ? _start : null,
                icon: const Icon(Icons.play_arrow),
                label: const Text('启动')),
            OutlinedButton.icon(
                onPressed: server.isRunning ? _stop : null,
                icon: const Icon(Icons.stop),
                label: const Text('停止')),
            OutlinedButton.icon(
                onPressed: server.url == null
                    ? null
                    : () async {
                        await Clipboard.setData(
                            ClipboardData(text: server.url!));
                        if (mounted) setState(() => _result = '地址已复制。');
                      },
                icon: const Icon(Icons.copy),
                label: const Text('复制地址')),
            OutlinedButton.icon(
                onPressed: () {
                  AppLogger.instance.marker('Manual diagnostic marker');
                  setState(() => _result = '已写入测试 Marker。');
                },
                icon: const Icon(Icons.bookmark_add_outlined),
                label: const Text('写入 Marker')),
            OutlinedButton.icon(
                onPressed: () {
                  AppLogger.instance.error('Manual diagnostic test error',
                      category: 'diagnostics',
                      event: 'manual_error',
                      error: StateError('Manual test error'),
                      stackTrace: StackTrace.current,
                      relatedFiles: const [
                        'lib/features/diagnostics/presentation/remote_devtools_diagnostics_page.dart'
                      ]);
                  setState(() => _result = '已写入真实测试异常日志。');
                },
                icon: const Icon(Icons.bug_report_outlined),
                label: const Text('生成异常测试')),
          ]),
          if (_result != null)
            Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(_result!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.primary))),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.only(top: 16),
                child: SelectableText('异常：$_error',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 24),
          const Text('支持平台', style: TextStyle(fontWeight: FontWeight.bold)),
          const Text(
              'Android ✓  iOS ✓  Windows ✓  macOS ✓  Linux ✓\nWeb 暂不支持（浏览器不能在应用内监听局域网 HTTP 端口）。'),
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 150, child: Text(label)),
          Expanded(child: SelectableText(value))
        ]),
      );
}
