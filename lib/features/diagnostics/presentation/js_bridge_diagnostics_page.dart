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
  String? _uploadTaskId;
  bool _working = false;

  // Track active JSBridge subscription IDs
  String? _networkSubId;
  String? _screenshotSubId;
  String? _themeSubId;
  String? _resizeSubId;
  String? _memorySubId;
  String? _accSubId;
  String? _gyroSubId;
  String? _proxSubId;
  String? _uploadSubId;

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

  Future<void> _toggleSubscription({
    required String onAction,
    required String offAction,
    required String? currentSubId,
    required ValueChanged<String?> onSubIdChanged,
    Map<String, Object?> onData = const {},
  }) async {
    if (currentSubId == null) {
      // Subscribe
      final response = await _invoke(onAction, onData);
      final data = response?['data'];
      if (data is Map && mounted) {
        final subId = data['subscriptionId']?.toString() ?? 'active';
        setState(() => onSubIdChanged(subId));
      }
    } else {
      // Unsubscribe
      final response = await _invoke(offAction, <String, Object?>{
        'subscriptionId': currentSubId,
      });
      if ((response?['success'] == true || response?['data'] is Map) &&
          mounted) {
        setState(() => onSubIdChanged(null));
      }
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
      appBar: AppBar(
        title: const Text('JS Bridge 测试'),
        actions: [
          IconButton(
            tooltip: '清空事件面板',
            icon: const Icon(Icons.clear_all),
            onPressed: () => setState(() => _events = '尚未收到事件。'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '模拟 WebView Bridge 请求/响应与事件流。支持基础 API 调用、文件上传任务，以及 9 项全局事件的订阅与显式注销。',
          ),
          const SizedBox(height: 12),

          // 1. Subscriptions Management Card
          _buildSubscriptionManagerCard(),
          const SizedBox(height: 16),

          // 2. Preset Buttons Categories
          Text(
            '快捷预设请求 (Presets)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          _buildPresetsSection(),
          const SizedBox(height: 16),

          // 3. Upload Test Card
          _UploadTaskTestCard(
            uploadUrlController: _uploadUrlController,
            selectedFileId: _selectedFileId,
            uploadSubscriptionId: _uploadSubId,
            uploadTaskId: _uploadTaskId,
            working: _working,
            onChooseFile: _chooseUploadFile,
            onSubscribe:
                () => _toggleSubscription(
                  onAction: 'file.onUploadEvent',
                  offAction: 'file.offUploadEvent',
                  currentSubId: _uploadSubId,
                  onSubIdChanged: (id) => _uploadSubId = id,
                ),
            onStart: _startUpload,
            onCancel: _cancelUpload,
            onUnsubscribe:
                () => _toggleSubscription(
                  onAction: 'file.onUploadEvent',
                  offAction: 'file.offUploadEvent',
                  currentSubId: _uploadSubId,
                  onSubIdChanged: (id) => _uploadSubId = id,
                ),
          ),
          const SizedBox(height: 20),

          // 4. Raw Request Editor
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

          // 5. Response Panel
          Text('响应 (Response)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _Panel(value: _response),
          const SizedBox(height: 20),

          // 6. Events Stream Panel
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '异步事件流 (Events Stream)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              TextButton(
                onPressed: () => setState(() => _events = '尚未收到事件。'),
                child: const Text('清空'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _Panel(value: _events),
        ],
      ),
    );
  }

  Widget _buildSubscriptionManagerCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.subscriptions,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'JSBridge 事件订阅与注销管理',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              '所有事件监听均支持生命周期独立订阅与注销，杜绝内存泄漏：',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const Divider(height: 20),
            _subscriptionRow(
              title: '网络状态变化',
              actionName: 'onNetworkStatusChange / offNetworkStatusChange',
              subId: _networkSubId,
              icon: Icons.wifi,
              onToggle:
                  () => _toggleSubscription(
                    onAction: 'onNetworkStatusChange',
                    offAction: 'offNetworkStatusChange',
                    currentSubId: _networkSubId,
                    onSubIdChanged: (id) => _networkSubId = id,
                  ),
            ),
            _subscriptionRow(
              title: '截屏主动捕获',
              actionName: 'onUserCaptureScreen / offUserCaptureScreen',
              subId: _screenshotSubId,
              icon: Icons.camera_alt,
              onToggle:
                  () => _toggleSubscription(
                    onAction: 'onUserCaptureScreen',
                    offAction: 'offUserCaptureScreen',
                    currentSubId: _screenshotSubId,
                    onSubIdChanged: (id) => _screenshotSubId = id,
                  ),
            ),
            _subscriptionRow(
              title: '加速度计 (~5次/秒)',
              actionName: 'onAccelerometerChange / offAccelerometerChange',
              subId: _accSubId,
              icon: Icons.speed,
              onToggle:
                  () => _toggleSubscription(
                    onAction: 'onAccelerometerChange',
                    offAction: 'offAccelerometerChange',
                    currentSubId: _accSubId,
                    onSubIdChanged: (id) => _accSubId = id,
                    onData: const {'interval': 200},
                  ),
            ),
            _subscriptionRow(
              title: '陀螺仪角速度',
              actionName: 'onGyroscopeChange / offGyroscopeChange',
              subId: _gyroSubId,
              icon: Icons.screen_rotation,
              onToggle:
                  () => _toggleSubscription(
                    onAction: 'onGyroscopeChange',
                    offAction: 'offGyroscopeChange',
                    currentSubId: _gyroSubId,
                    onSubIdChanged: (id) => _gyroSubId = id,
                    onData: const {'interval': 200},
                  ),
            ),
            _subscriptionRow(
              title: '距离传感器 (贴近)',
              actionName: 'onProximityChange / offProximityChange',
              subId: _proxSubId,
              icon: Icons.sensors,
              onToggle:
                  () => _toggleSubscription(
                    onAction: 'onProximityChange',
                    offAction: 'offProximityChange',
                    currentSubId: _proxSubId,
                    onSubIdChanged: (id) => _proxSubId = id,
                  ),
            ),
            _subscriptionRow(
              title: '系统明暗主题',
              actionName: 'onThemeChange / offThemeChange',
              subId: _themeSubId,
              icon: Icons.brightness_6,
              onToggle:
                  () => _toggleSubscription(
                    onAction: 'onThemeChange',
                    offAction: 'offThemeChange',
                    currentSubId: _themeSubId,
                    onSubIdChanged: (id) => _themeSubId = id,
                  ),
            ),
            _subscriptionRow(
              title: '窗口与旋转尺寸',
              actionName: 'onResize / offResize',
              subId: _resizeSubId,
              icon: Icons.aspect_ratio,
              onToggle:
                  () => _toggleSubscription(
                    onAction: 'onResize',
                    offAction: 'offResize',
                    currentSubId: _resizeSubId,
                    onSubIdChanged: (id) => _resizeSubId = id,
                  ),
            ),
            _subscriptionRow(
              title: '系统低内存告警',
              actionName: 'onMemoryWarning / offMemoryWarning',
              subId: _memorySubId,
              icon: Icons.memory,
              onToggle:
                  () => _toggleSubscription(
                    onAction: 'onMemoryWarning',
                    offAction: 'offMemoryWarning',
                    currentSubId: _memorySubId,
                    onSubIdChanged: (id) => _memorySubId = id,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _subscriptionRow({
    required String title,
    required String actionName,
    required String? subId,
    required IconData icon,
    required VoidCallback onToggle,
  }) {
    final isSubscribed = subId != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: isSubscribed ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  isSubscribed ? '已订阅 (ID: $subId)' : '未订阅 · $actionName',
                  style: TextStyle(
                    fontSize: 11,
                    color: isSubscribed ? Colors.green.shade700 : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: isSubscribed
                ? OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _working ? null : onToggle,
                    child: const Text('取消订阅'),
                  )
                : FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _working ? null : onToggle,
                    child: const Text('订阅 (on)'),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Basic & Device API Presets
        const Text(
          '1. 基础与设备控制 API',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            OutlinedButton(
              onPressed: () => _preset('sys-info', 'getSystemInfo'),
              child: const Text('系统信息'),
            ),
            OutlinedButton(
              onPressed: () => _preset('dev-info', 'getDeviceInfo'),
              child: const Text('设备信息'),
            ),
            OutlinedButton(
              onPressed: () => _preset('net-type', 'getNetworkType'),
              child: const Text('网络类型'),
            ),
            OutlinedButton(
              onPressed: () => _preset('wifi-info', 'getWifiInfo'),
              child: const Text('Wi-Fi 信息'),
            ),
            OutlinedButton(
              onPressed:
                  () => _preset('wifi-permission', 'requestWifiInfoPermission'),
              child: const Text('Wi-Fi 权限'),
            ),
            OutlinedButton(
              onPressed: () => _preset('wifi-settings', 'openWifiSettings'),
              child: const Text('Wi-Fi 设置'),
            ),
            OutlinedButton(
              onPressed:
                  () => _preset(
                    'photo-permission',
                    'requestPermission',
                    <String, Object?>{'permission': 'photos'},
                  ),
              child: const Text('相册权限'),
            ),
            OutlinedButton(
              onPressed:
                  () => _preset(
                    'camera-permission',
                    'requestPermission',
                    <String, Object?>{'permission': 'camera'},
                  ),
              child: const Text('相机权限'),
            ),
            OutlinedButton(
              onPressed: () => _preset('app-settings', 'openAppSettings'),
              child: const Text('应用设置'),
            ),
            OutlinedButton(
              onPressed: () => _preset('battery', 'getBatteryInfo'),
              child: const Text('电池电量'),
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
                    'set-bri',
                    'setScreenBrightness',
                    <String, Object?>{'value': 0.8},
                  ),
              child: const Text('设置亮度 (0.8)'),
            ),
            OutlinedButton(
              onPressed:
                  () => _preset('flash-on', 'setFlashlight', <String, Object?>{
                    'enabled': true,
                  }),
              child: const Text('开启闪光灯'),
            ),
            OutlinedButton(
              onPressed:
                  () => _preset('flash-off', 'setFlashlight', <String, Object?>{
                    'enabled': false,
                  }),
              child: const Text('关闭闪光灯'),
            ),
            OutlinedButton(
              onPressed: () => _preset('volume', 'getSystemVolume'),
              child: const Text('读取音量'),
            ),
            OutlinedButton(
              onPressed:
                  () => _preset(
                    'set-volume',
                    'setSystemVolume',
                    <String, Object?>{'value': 0.5},
                  ),
              child: const Text('设置音量 (0.5)'),
            ),
            OutlinedButton(
              onPressed:
                  () => _preset(
                    'desktop-badge',
                    'setDesktopBadge',
                    <String, Object?>{'count': 7},
                  ),
              child: const Text('桌面角标 (7)'),
            ),
            OutlinedButton(
              onPressed:
                  () => _preset('call', 'makePhoneCall', <String, Object?>{
                    'phoneNumber': '10086',
                  }),
              child: const Text('拨打电话'),
            ),
            OutlinedButton(
              onPressed:
                  () => _preset('file-single', 'chooseFile', <String, Object?>{
                    'allowMultiple': false,
                  }),
              child: const Text('单选文件'),
            ),
            OutlinedButton(
              onPressed:
                  () => _preset('file-multi', 'chooseFile', <String, Object?>{
                    'allowMultiple': true,
                    'maxCount': 5,
                    'allowedExtensions': ['pdf', 'docx', 'xlsx', 'txt'],
                  }),
              child: const Text('多选文件 (限5/文档)'),
            ),
            OutlinedButton(
              onPressed:
                  () => _preset('img-single', 'chooseImage', <String, Object?>{
                    'allowMultiple': false,
                  }),
              child: const Text('单选图片'),
            ),
            OutlinedButton(
              onPressed:
                  () => _preset('img-multi', 'chooseImage', <String, Object?>{
                    'allowMultiple': true,
                    'maxCount': 9,
                  }),
              child: const Text('多选图片 (限9张)'),
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
        const SizedBox(height: 10),

        // 2. Subscribe (on*) Presets
        const Text(
          '2. 事件订阅 (on*)',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: Colors.green,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            OutlinedButton(
              onPressed:
                  () => _preset('sub-net', 'onNetworkStatusChange', const {
                    'subscriptionId': 'net-1',
                  }),
              child: const Text('订阅网络 (on)'),
            ),
            OutlinedButton(
              onPressed:
                  () => _preset('sub-ss', 'onUserCaptureScreen', const {
                    'subscriptionId': 'ss-1',
                  }),
              child: const Text('订阅截屏 (on)'),
            ),
            OutlinedButton(
              onPressed:
                  () => _preset('sub-acc', 'onAccelerometerChange', const {
                    'subscriptionId': 'acc-1',
                    'interval': 200,
                  }),
              child: const Text('订阅加速度 (on)'),
            ),
            OutlinedButton(
              onPressed:
                  () => _preset('sub-gyro', 'onGyroscopeChange', const {
                    'subscriptionId': 'gyro-1',
                    'interval': 200,
                  }),
              child: const Text('订阅陀螺仪 (on)'),
            ),
            OutlinedButton(
              onPressed:
                  () => _preset('sub-prox', 'onProximityChange', const {
                    'subscriptionId': 'prox-1',
                  }),
              child: const Text('订阅距离 (on)'),
            ),
            OutlinedButton(
              onPressed:
                  () => _preset('sub-theme', 'onThemeChange', const {
                    'subscriptionId': 'theme-1',
                  }),
              child: const Text('订阅主题 (on)'),
            ),
            OutlinedButton(
              onPressed:
                  () => _preset('sub-resize', 'onResize', const {
                    'subscriptionId': 'resize-1',
                  }),
              child: const Text('订阅尺寸 (on)'),
            ),
            OutlinedButton(
              onPressed:
                  () => _preset('sub-mem', 'onMemoryWarning', const {
                    'subscriptionId': 'mem-1',
                  }),
              child: const Text('订阅内存告警 (on)'),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // 3. Unsubscribe (off*) Presets
        const Text(
          '3. 取消订阅 (off*)',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: Colors.red,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            OutlinedButton(
              onPressed:
                  () => _preset('off-net', 'offNetworkStatusChange', const {
                    'subscriptionId': 'net-1',
                  }),
              child: const Text('取消网络 (off)'),
            ),
            OutlinedButton(
              onPressed:
                  () => _preset('off-ss', 'offUserCaptureScreen', const {
                    'subscriptionId': 'ss-1',
                  }),
              child: const Text('取消截屏 (off)'),
            ),
            OutlinedButton(
              onPressed:
                  () => _preset('off-acc', 'offAccelerometerChange', const {
                    'subscriptionId': 'acc-1',
                  }),
              child: const Text('取消加速度 (off)'),
            ),
            OutlinedButton(
              onPressed:
                  () => _preset('off-gyro', 'offGyroscopeChange', const {
                    'subscriptionId': 'gyro-1',
                  }),
              child: const Text('取消陀螺仪 (off)'),
            ),
            OutlinedButton(
              onPressed:
                  () => _preset('off-prox', 'offProximityChange', const {
                    'subscriptionId': 'prox-1',
                  }),
              child: const Text('取消距离 (off)'),
            ),
            OutlinedButton(
              onPressed:
                  () => _preset('off-theme', 'offThemeChange', const {
                    'subscriptionId': 'theme-1',
                  }),
              child: const Text('取消主题 (off)'),
            ),
            OutlinedButton(
              onPressed:
                  () => _preset('off-resize', 'offResize', const {
                    'subscriptionId': 'resize-1',
                  }),
              child: const Text('取消尺寸 (off)'),
            ),
            OutlinedButton(
              onPressed:
                  () => _preset('off-mem', 'offMemoryWarning', const {
                    'subscriptionId': 'mem-1',
                  }),
              child: const Text('取消内存告警 (off)'),
            ),
          ],
        ),
      ],
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
          tooltip: '复制内容',
          icon: const Icon(Icons.copy, size: 20),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: value));
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
            }
          },
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
  final VoidCallback onChooseFile;
  final VoidCallback onSubscribe;
  final VoidCallback onStart;
  final VoidCallback onCancel;
  final VoidCallback onUnsubscribe;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('文件上传与进度事件闭环', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              '完整链路：选择文件 → 订阅上传事件 → 发起上传任务 → 接收 progress/completed 事件 → 取消或退订。',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: uploadUrlController,
              decoration: const InputDecoration(
                labelText: '上传目标 URL (必须在白名单内)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: working ? null : onChooseFile,
                  child: const Text('1. 选择待传文件'),
                ),
                OutlinedButton(
                  onPressed: working ? null : onSubscribe,
                  child: Text(
                    uploadSubscriptionId == null ? '2. 订阅上传事件' : '2. 已订阅上传',
                  ),
                ),
                FilledButton(
                  onPressed: working ? null : onStart,
                  child: const Text('3. 发起上传任务'),
                ),
                OutlinedButton(
                  onPressed: working || uploadTaskId == null ? null : onCancel,
                  child: const Text('4. 取消上传'),
                ),
                OutlinedButton(
                  onPressed:
                      working || uploadSubscriptionId == null
                          ? null
                          : onUnsubscribe,
                  child: const Text('5. 取消上传订阅'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '当前已选 fileId: ${selectedFileId ?? '未选择'}\n'
              '当前上传 subscriptionId: ${uploadSubscriptionId ?? '未订阅'}\n'
              '当前 taskId: ${uploadTaskId ?? '未创建'}',
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    );
  }
}

String _pretty(Object? value) =>
    const JsonEncoder.withIndent('  ').convert(value);
