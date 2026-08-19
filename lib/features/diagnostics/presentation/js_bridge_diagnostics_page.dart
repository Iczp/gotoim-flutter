import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/application_providers.dart';

class JsBridgeDiagnosticsPage extends ConsumerStatefulWidget {
  const JsBridgeDiagnosticsPage({super.key});

  @override
  ConsumerState<JsBridgeDiagnosticsPage> createState() =>
      _JsBridgeDiagnosticsPageState();
}

class _JsBridgeDiagnosticsPageState
    extends ConsumerState<JsBridgeDiagnosticsPage> {
  final _requestController = TextEditingController(
    text:
        '{\n  "id": "diagnostic-system",\n  "action": "getSystemInfo",\n  "data": {}\n}',
  );
  StreamSubscription? _eventsSubscription;
  String _response = '尚未调用。';
  String _events = '尚未收到事件。';
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _eventsSubscription = ref.read(jsApiDispatcherProvider).events.listen((
      event,
    ) {
      if (mounted) setState(() => _events = _pretty(event.toJson()));
    });
  }

  @override
  void dispose() {
    _eventsSubscription?.cancel();
    _requestController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _working = true);
    final response = await ref
        .read(jsApiDispatcherProvider)
        .handleRaw(_requestController.text);
    if (mounted) {
      setState(() {
        _response = _formatResponse(response);
        _working = false;
      });
    }
  }

  void _preset(
    String id,
    String action, [
    Map<String, Object?> data = const {},
  ]) {
    _requestController.text = _pretty(<String, Object?>{
      'id': id,
      'action': action,
      'data': data,
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(body: Center(child: Text('开发诊断仅在 Debug 模式可用。')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('JS Bridge 测试')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '模拟 WebView JavaScriptChannel 输入。填写 JSON 请求，调用后显示完整 JSON 响应；订阅网络事件后，切换网络可看到事件 payload。',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => _preset('system', 'getSystemInfo'),
                child: const Text('系统信息'),
              ),
              OutlinedButton(
                onPressed: () => _preset('device', 'getDeviceInfo'),
                child: const Text('设备信息'),
              ),
              OutlinedButton(
                onPressed: () => _preset('network', 'getNetworkType'),
                child: const Text('网络类型'),
              ),
              OutlinedButton(
                onPressed: () => _preset('capabilities', 'getCapabilities'),
                child: const Text('能力清单'),
              ),
              OutlinedButton(
                onPressed:
                    () => _preset('network-watch', 'onNetworkStatusChange'),
                child: const Text('订阅网络'),
              ),
              OutlinedButton(
                onPressed:
                    () => _preset('file', 'chooseFile', <String, Object?>{
                      'allowMultiple': false,
                    }),
                child: const Text('选择文件'),
              ),
              OutlinedButton(
                onPressed:
                    () => _preset('image', 'chooseImage', <String, Object?>{
                      'allowMultiple': false,
                    }),
                child: const Text('选择图片'),
              ),
              OutlinedButton(
                onPressed: () => _preset('photo', 'takePhoto'),
                child: const Text('拍照'),
              ),
              OutlinedButton(
                onPressed: () => _preset('audio', 'startAudioRecording'),
                child: const Text('开始录音'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _requestController,
            minLines: 8,
            maxLines: 16,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: const InputDecoration(
              labelText: 'Bridge 请求 JSON',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _working ? null : _send,
            child:
                _working
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Text('调用 handleRaw'),
          ),
          const SizedBox(height: 20),
          Text('响应', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _Panel(value: _response),
          const SizedBox(height: 20),
          Text('异步事件', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _Panel(value: _events),
        ],
      ),
    );
  }

  String _formatResponse(String response) {
    try {
      return _pretty(jsonDecode(response));
    } on FormatException {
      return response;
    }
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.value});

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
