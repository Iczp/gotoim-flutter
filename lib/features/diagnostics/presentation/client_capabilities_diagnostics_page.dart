import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/application_providers.dart';
import '../../../core/capabilities/client_capability_models.dart';
import '../../../core/services/file/file_picker_service.dart';

class ClientCapabilitiesDiagnosticsPage extends ConsumerStatefulWidget {
  const ClientCapabilitiesDiagnosticsPage({super.key});

  @override
  ConsumerState<ClientCapabilitiesDiagnosticsPage> createState() =>
      _ClientCapabilitiesDiagnosticsPageState();
}

class _ClientCapabilitiesDiagnosticsPageState
    extends ConsumerState<ClientCapabilitiesDiagnosticsPage> {
  final _clipboardController = TextEditingController(text: 'Goto IM clipboard');
  StreamSubscription<ClientNetworkStatus>? _networkSubscription;
  String _result = '尚未调用。';
  bool _working = false;
  bool _watchingNetwork = false;

  @override
  void dispose() {
    _clipboardController.dispose();
    _networkSubscription?.cancel();
    super.dispose();
  }

  Future<void> _run(Future<Object?> Function() call) async {
    setState(() => _working = true);
    try {
      final data = await call();
      if (mounted) setState(() => _result = _pretty(data));
    } catch (error) {
      if (mounted) setState(() => _result = '调用失败：$error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _toggleNetworkWatch() async {
    if (_watchingNetwork) {
      await _networkSubscription?.cancel();
      _networkSubscription = null;
      if (mounted) setState(() => _watchingNetwork = false);
      return;
    }
    final service = ref.read(clientCapabilityServiceProvider);
    _networkSubscription = service.networkStatusChanges.listen((status) {
      if (mounted) {
        setState(
          () =>
              _result = _pretty(<String, Object>{
                'event': 'network.statusChange',
                'data': status.toJson(),
              }),
        );
      }
    });
    setState(() => _watchingNetwork = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(body: Center(child: Text('开发诊断仅在 Debug 模式可用。')));
    }
    final capabilities = ref.read(clientCapabilityServiceProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('客户端能力中心')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('每次调用都会将统一 API 的实际返回值显示在底部。网络类型表示系统网络传输状态，不代表互联网一定可访问。'),
          const SizedBox(height: 16),
          _Section(
            title: '一级：系统与设备',
            description: '窗口尺寸、安全区、语言、主题、应用标识和非敏感设备元数据。',
            children: [
              _button(
                'getSystemInfo',
                () => _run(
                  () async => (await capabilities.getSystemInfo()).toJson(),
                ),
              ),
              _button(
                'getDeviceInfo',
                () => _run(
                  () async => (await capabilities.getDeviceInfo()).toJson(),
                ),
              ),
              _button(
                'getCapabilities',
                () => _run(
                  () async => <String, Object>{
                    'capabilities':
                        (await capabilities.getCapabilities())
                            .map((item) => item.toJson())
                            .toList(),
                  },
                ),
              ),
            ],
          ),
          _Section(
            title: '一级：网络',
            description: '当前网络类型，以及可取消的状态变化监听。',
            children: [
              _button(
                'getNetworkType',
                () => _run(
                  () async => (await capabilities.getNetworkType()).toJson(),
                ),
              ),
              _button(
                _watchingNetwork
                    ? '停止 onNetworkStatusChange'
                    : '开始 onNetworkStatusChange',
                _working ? null : _toggleNetworkWatch,
              ),
            ],
          ),
          _Section(
            title: '一级：剪贴板与文件',
            description: '文件选择只返回安全元数据；不会把本机绝对路径或二进制内容暴露给诊断/H5。',
            children: [
              TextField(
                controller: _clipboardController,
                decoration: const InputDecoration(
                  labelText: '剪贴板文本',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              _button(
                'setClipboardData',
                () => _run(() async {
                  await capabilities.setClipboardData(
                    _clipboardController.text,
                  );
                  return const <String, bool>{'ok': true};
                }),
              ),
              _button(
                'getClipboardData',
                () => _run(
                  () async => <String, String?>{
                    'data': await capabilities.getClipboardData(),
                  },
                ),
              ),
              _button(
                'chooseFile（单选）',
                () => _run(
                  () async => <String, Object>{
                    'files':
                        (await capabilities.chooseFile(
                          const FilePickerRequest(),
                        )).map((item) => item.toJson()).toList(),
                  },
                ),
              ),
              _button(
                'chooseFile（多选，图片）',
                () => _run(
                  () async => <String, Object>{
                    'files':
                        (await capabilities.chooseFile(
                          const FilePickerRequest(
                            allowMultiple: true,
                            allowedExtensions: <String>[
                              'png',
                              'jpg',
                              'jpeg',
                              'webp',
                            ],
                            dialogTitle: '选择图片',
                          ),
                        )).map((item) => item.toJson()).toList(),
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('调用返回', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _ResultPanel(value: _result),
        ],
      ),
    );
  }

  Widget _button(String label, VoidCallback? onPressed) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: FilledButton.tonal(
      onPressed: _working ? null : onPressed,
      child: Text(label),
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.description,
    required this.children,
  });

  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(description),
          ...children,
        ],
      ),
    ),
  );
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
    ),
    child: SelectableText(
      value,
      style: const TextStyle(fontFamily: 'monospace'),
    ),
  );
}

String _pretty(Object? value) =>
    const JsonEncoder.withIndent('  ').convert(value);
