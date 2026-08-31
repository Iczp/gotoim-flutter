import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/application_providers.dart';

class DeviceRegistrationDiagnosticsPage extends ConsumerStatefulWidget {
  const DeviceRegistrationDiagnosticsPage({super.key});

  @override
  ConsumerState<DeviceRegistrationDiagnosticsPage> createState() =>
      _DeviceRegistrationDiagnosticsPageState();
}

class _DeviceRegistrationDiagnosticsPageState
    extends ConsumerState<DeviceRegistrationDiagnosticsPage> {
  final _name = TextEditingController(text: 'Goto IM');
  String _result = '未执行';
  bool _working = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _collect() async {
    await _run(
      () async => ref
          .read(deviceRegistrationApiProvider)
          .collectPayload(name: _name.text),
    );
  }

  Future<void> _register() async {
    await _run(
      () async => <String, Object?>{
        'response': await ref
            .read(deviceRegistrationApiProvider)
            .register(name: _name.text),
      },
    );
  }

  Future<void> _run(Future<Object?> Function() action) async {
    setState(() => _working = true);
    final started = DateTime.now();
    try {
      final value = await action();
      if (mounted) {
        setState(
          () =>
              _result = const JsonEncoder.withIndent('  ').convert({
                'status': '成功',
                'elapsedMs': DateTime.now().difference(started).inMilliseconds,
                'data': value,
              }),
        );
      }
    } catch (error, stackTrace) {
      if (mounted) {
        setState(
          () =>
              _result = const JsonEncoder.withIndent('  ').convert({
                'status': '失败',
                'elapsedMs': DateTime.now().difference(started).inMilliseconds,
                'exceptionType': error.runtimeType.toString(),
                'message': error.toString(),
                'stackTrace': stackTrace.toString(),
              }),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(body: Center(child: Text('开发诊断仅在 Debug 模式可用。')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('设备注册与信息采集')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'POST /api/chat/device/register；Android、iOS、Windows、macOS、Linux、Web 均可调用。先使用 client_credentials（scope=IM）获取独立 Token，再以 Bearer 调用注册接口。',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: '设备显示名称',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _working ? null : _collect,
                child: const Text('采集并查看 Payload'),
              ),
              FilledButton(
                onPressed: _working ? null : _register,
                child: Text(_working ? '执行中…' : '实际注册设备'),
              ),
              TextButton(
                onPressed:
                    _working
                        ? null
                        : () => setState(() {
                          _name.text = 'Goto IM';
                          _result = '未执行';
                        }),
                child: const Text('恢复默认'),
              ),
              TextButton.icon(
                onPressed:
                    () => Clipboard.setData(ClipboardData(text: _result)),
                icon: const Icon(Icons.copy_outlined),
                label: const Text('复制结果'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('实际执行结果'),
          const SizedBox(height: 8),
          SelectableText(_result),
        ],
      ),
    );
  }
}
