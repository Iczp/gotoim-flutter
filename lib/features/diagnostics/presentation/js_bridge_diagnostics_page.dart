import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../app/application_providers.dart';
import '../../../core/config/app_environment.dart';

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
  final _uploadUrlController = TextEditingController();
  StreamSubscription? _eventsSubscription;
  String _response = '尚未调用。';
  String _events = '尚未收到事件。';
  String? _selectedFileId;
  String? _uploadSubscriptionId;
  String? _uploadTaskId;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _uploadUrlController.text =
        ref.read(appEnvironmentProvider).jsBridgeUploadUrl.trim();
    _eventsSubscription = ref.read(jsApiDispatcherProvider).events.listen((
      event,
    ) {
      if (!mounted) return;
      final formatted = _pretty(event.toJson());
      setState(() {
        _events = _events == '尚未收到事件。' ? formatted : '$_events\n\n$formatted';
      });
    });
  }

  @override
  void dispose() {
    _eventsSubscription?.cancel();
    _requestController.dispose();
    _uploadUrlController.dispose();
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

  Future<Map<String, dynamic>?> _invoke(
    String action, [
    Map<String, Object?> data = const {},
  ]) async {
    if (_working) return null;
    setState(() => _working = true);
    final raw = await ref
        .read(jsApiDispatcherProvider)
        .handleRaw(
          _pretty(<String, Object?>{
            'id': 'diagnostic-${DateTime.now().microsecondsSinceEpoch}',
            'action': action,
            'data': data,
          }),
        );
    final formatted = _formatResponse(raw);
    if (!mounted) return null;
    setState(() {
      _response = formatted;
      _working = false;
    });
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } on FormatException {
      return null;
    }
  }

  Future<void> _chooseUploadFile() async {
    final response = await _invoke('file.chooseFile', <String, Object?>{
      'allowMultiple': false,
    });
    final data = response?['data'];
    final files = data is Map ? data['files'] : null;
    final first = files is List && files.isNotEmpty ? files.first : null;
    if (first is! Map || !mounted) return;
    setState(() {
      _selectedFileId = first['fileId']?.toString();
      _uploadTaskId = null;
    });
  }

  Future<void> _subscribeUpload() async {
    final response = await _invoke('file.onUploadEvent');
    final data = response?['data'];
    if (data is Map && mounted) {
      setState(
        () => _uploadSubscriptionId = data['subscriptionId']?.toString(),
      );
    }
  }

  Future<void> _startUpload() async {
    final fileId = _selectedFileId;
    final url = _uploadUrlController.text.trim();
    if (fileId == null || url.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先选择文件并填写上传地址。')));
      return;
    }
    final response = await _invoke('file.upload', <String, Object?>{
      'fileId': fileId,
      'uploadUrl': url,
      'method': 'POST',
      'multipart': true,
      'fieldName': 'file',
      'headers': <String, Object?>{},
      'formData': <String, Object?>{},
      'timeoutSeconds': 60,
    });
    final data = response?['data'];
    final task = data is Map ? data['task'] : null;
    if (task is Map && mounted) {
      setState(() => _uploadTaskId = task['taskId']?.toString());
    }
  }

  Future<void> _cancelUpload() async {
    final taskId = _uploadTaskId;
    if (taskId == null) return;
    await _invoke('file.cancelUpload', <String, Object?>{'taskId': taskId});
  }

  Future<void> _unsubscribeUpload() async {
    final subscriptionId = _uploadSubscriptionId;
    if (subscriptionId == null) return;
    final response = await _invoke('file.offUploadEvent', <String, Object?>{
      'subscriptionId': subscriptionId,
    });
    if (response?['success'] == true && mounted) {
      setState(() => _uploadSubscriptionId = null);
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
            '模拟 WebView Bridge 输入。填写 JSON 请求，调用后显示完整 JSON 响应；订阅网络事件后，切换网络可看到事件 payload。',
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
              OutlinedButton(
                onPressed: () => _preset('battery', 'getBatteryInfo'),
                child: const Text('电量查询'),
              ),
              OutlinedButton(
                onPressed:
                    () => _preset('vibrate', 'vibrate', <String, Object?>{
                      'style': 'medium',
                      'duration': 200,
                    }),
                child: const Text('设备振动'),
              ),
              OutlinedButton(
                onPressed: () => _preset('brightness', 'getScreenBrightness'),
                child: const Text('读取亮度'),
              ),
              OutlinedButton(
                onPressed:
                    () => _preset(
                      'set-brightness',
                      'setScreenBrightness',
                      <String, Object?>{'value': 0.8},
                    ),
                child: const Text('设置亮度'),
              ),
              OutlinedButton(
                onPressed:
                    () => _preset(
                      'call',
                      'makePhoneCall',
                      <String, Object?>{'phoneNumber': '10086'},
                    ),
                child: const Text('拨打电话'),
              ),
              OutlinedButton(
                onPressed:
                    () => _preset('screenshot', 'onUserCaptureScreen'),
                child: const Text('截屏监听'),
              ),
              OutlinedButton(
                onPressed:
                    () => _preset(
                      'acc',
                      'onAccelerometerChange',
                      <String, Object?>{'interval': 200},
                    ),
                child: const Text('加速度计'),
              ),
              OutlinedButton(
                onPressed:
                    () => _preset(
                      'gyro',
                      'onGyroscopeChange',
                      <String, Object?>{'interval': 200},
                    ),
                child: const Text('陀螺仪'),
              ),
              OutlinedButton(
                onPressed: () => _preset('prox', 'onProximityChange'),
                child: const Text('距离传感器'),
              ),
              OutlinedButton(
                onPressed: () => _preset('theme', 'onThemeChange'),
                child: const Text('主题变化'),
              ),
              OutlinedButton(
                onPressed: () => _preset('memory', 'onMemoryWarning'),
                child: const Text('内存告警'),
              ),
              OutlinedButton(
                onPressed: () => _preset('resize', 'onResize'),
                child: const Text('窗口尺寸'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _UploadTaskTestCard(
            uploadUrlController: _uploadUrlController,
            selectedFileId: _selectedFileId,
            uploadSubscriptionId: _uploadSubscriptionId,
            uploadTaskId: _uploadTaskId,
            working: _working,
            onChooseFile: _chooseUploadFile,
            onSubscribe: _subscribeUpload,
            onStart: _startUpload,
            onCancel: _cancelUpload,
            onUnsubscribe: _unsubscribeUpload,
          ),
          const SizedBox(height: 20),
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
    padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
        IconButton(
          tooltip: '复制 JSON',
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: value));
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('内容已复制')));
            }
          },
          icon: const Icon(Icons.copy_outlined),
        ),
      ],
    ),
  );
}

class _UploadTaskTestCard extends StatelessWidget {
  const _UploadTaskTestCard({
    required this.uploadUrlController,
    required this.selectedFileId,
    required this.uploadSubscriptionId,
    required this.uploadTaskId,
    required this.working,
    required this.onChooseFile,
    required this.onSubscribe,
    required this.onStart,
    required this.onCancel,
    required this.onUnsubscribe,
  });

  final TextEditingController uploadUrlController;
  final String? selectedFileId;
  final String? uploadSubscriptionId;
  final String? uploadTaskId;
  final bool working;
  final Future<void> Function() onChooseFile;
  final Future<void> Function() onSubscribe;
  final Future<void> Function() onStart;
  final Future<void> Function() onCancel;
  final Future<void> Function() onUnsubscribe;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('文件上传任务测试', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text('选择文件 → 订阅事件 → 开始上传；完整请求、响应和进度事件显示在下方，均可复制。'),
          const SizedBox(height: 12),
          TextField(
            controller: uploadUrlController,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: '测试上传地址（环境配置）',
              hintText: 'http://10.0.5.20:4173/upload',
              border: OutlineInputBorder(),
            ),
            readOnly: true,
          ),
          const SizedBox(height: 8),
          SelectionArea(
            child: Text(
              '文件: ${selectedFileId ?? '未选择'}\n'
              '上传订阅: ${uploadSubscriptionId ?? '未订阅'}\n'
              '任务: ${uploadTaskId ?? '未开始'}',
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: working ? null : onChooseFile,
                child: const Text('1. 选择文件'),
              ),
              OutlinedButton(
                onPressed:
                    working || uploadSubscriptionId != null
                        ? null
                        : onSubscribe,
                child: const Text('2. 订阅上传事件'),
              ),
              FilledButton(
                onPressed: working || selectedFileId == null ? null : onStart,
                child: const Text('3. 开始上传'),
              ),
              OutlinedButton(
                onPressed: working || uploadTaskId == null ? null : onCancel,
                child: const Text('取消任务'),
              ),
              TextButton(
                onPressed:
                    working || uploadSubscriptionId == null
                        ? null
                        : onUnsubscribe,
                child: const Text('取消上传订阅'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

String _pretty(Object? value) =>
    const JsonEncoder.withIndent('  ').convert(value);
