import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/native/native.dart';

/// Development Diagnostics Center - Native / Device Capabilities Page.
///
/// Features:
/// - Screen Capture (Screenshot) event detection
/// - Vibration / Haptic Feedback (timed and semantic impacts)
/// - System Theme brightness changes
/// - System Memory Pressure warnings
/// - Accelerometer (~5 times/second live values)
/// - Gyroscope (live rotation values)
/// - Proximity Sensor (near/far status)
/// - Screen Brightness adjustment & query
/// - Battery Info & charging state
/// - Window Resize & orientation changes
/// - Phone Call dialer launch
class NativeDiagnosticsPage extends ConsumerStatefulWidget {
  const NativeDiagnosticsPage({super.key});

  @override
  ConsumerState<NativeDiagnosticsPage> createState() => _NativeDiagnosticsPageState();
}

class _NativeDiagnosticsPageState extends ConsumerState<NativeDiagnosticsPage> {
  // System State
  late Brightness _currentBrightness;
  late Size _currentWindowSize;
  int _memoryWarningCount = 0;
  DateTime? _lastMemoryWarning;
  final List<String> _screenshotEvents = [];
  final List<String> _themeEvents = [];
  final List<String> _resizeEvents = [];

  // Device State
  BatteryInfo? _batteryInfo;
  double _screenBrightness = 1.0;
  final TextEditingController _phoneController = TextEditingController(text: '10086');
  String _vibrateStatus = '就绪';

  // Sensor State
  AccelerometerEvent? _accelerometerEvent;
  GyroscopeEvent? _gyroscopeEvent;
  ProximityEvent? _proximityEvent;

  bool _listeningAccelerometer = false;
  bool _listeningGyroscope = false;
  bool _listeningProximity = false;

  // Subscriptions
  StreamSubscription<Brightness>? _themeSub;
  StreamSubscription<Size>? _resizeSub;
  StreamSubscription<DateTime>? _memorySub;
  StreamSubscription<DateTime>? _screenshotSub;
  StreamSubscription<AccelerometerEvent>? _accelerometerSub;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSub;
  StreamSubscription<ProximityEvent>? _proximitySub;

  @override
  void initState() {
    super.initState();
    _currentBrightness = Native.system.currentBrightness;
    _currentWindowSize = Native.system.currentWindowSize;

    _subscribeSystemEvents();
    _fetchDeviceStatus();
  }

  void _subscribeSystemEvents() {
    // Theme
    _themeSub = Native.system.onThemeChange.listen((brightness) {
      if (mounted) {
        setState(() {
          _currentBrightness = brightness;
          _themeEvents.insert(0, '${_formatTime(DateTime.now())} - 切换为 ${brightness.name.toUpperCase()}');
          if (_themeEvents.length > 10) _themeEvents.removeLast();
        });
      }
    });

    // Resize
    _resizeSub = Native.system.onResize.listen((size) {
      if (mounted) {
        setState(() {
          _currentWindowSize = size;
          _resizeEvents.insert(
            0,
            '${_formatTime(DateTime.now())} - 尺寸 ${size.width.toInt()}x${size.height.toInt()}',
          );
          if (_resizeEvents.length > 10) _resizeEvents.removeLast();
        });
      }
    });

    // Memory warning
    _memorySub = Native.system.onMemoryWarning.listen((timestamp) {
      if (mounted) {
        setState(() {
          _memoryWarningCount++;
          _lastMemoryWarning = timestamp;
        });
      }
    });

    // Screenshot
    _screenshotSub = Native.system.onUserCaptureScreen.listen((timestamp) {
      if (mounted) {
        setState(() {
          _screenshotEvents.insert(0, '${_formatTime(timestamp)} - 检测到主动截屏');
          if (_screenshotEvents.length > 10) _screenshotEvents.removeLast();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📸 捕获到用户截屏事件！'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    });
  }

  Future<void> _fetchDeviceStatus() async {
    final battery = await Native.getBatteryInfo();
    final brightness = await Native.getScreenBrightness();
    if (mounted) {
      setState(() {
        _batteryInfo = battery;
        _screenBrightness = brightness;
      });
    }
  }

  void _toggleAccelerometer(bool enable) {
    if (enable) {
      _accelerometerSub = Native.onAccelerometerChange((event) {
        if (mounted) {
          setState(() => _accelerometerEvent = event);
        }
      });
      setState(() => _listeningAccelerometer = true);
    } else {
      _accelerometerSub?.cancel();
      _accelerometerSub = null;
      Native.offAccelerometer();
      setState(() => _listeningAccelerometer = false);
    }
  }

  void _toggleGyroscope(bool enable) {
    if (enable) {
      _gyroscopeSub = Native.onGyroscopeChange((event) {
        if (mounted) {
          setState(() => _gyroscopeEvent = event);
        }
      });
      setState(() => _listeningGyroscope = true);
    } else {
      _gyroscopeSub?.cancel();
      _gyroscopeSub = null;
      Native.offGyroscope();
      setState(() => _listeningGyroscope = false);
    }
  }

  void _toggleProximity(bool enable) {
    if (enable) {
      _proximitySub = Native.onProximityChange((event) {
        if (mounted) {
          setState(() => _proximityEvent = event);
        }
      });
      setState(() => _listeningProximity = true);
    } else {
      _proximitySub?.cancel();
      _proximitySub = null;
      Native.offProximity();
      setState(() => _listeningProximity = false);
    }
  }

  @override
  void dispose() {
    _themeSub?.cancel();
    _resizeSub?.cancel();
    _memorySub?.cancel();
    _screenshotSub?.cancel();
    _accelerometerSub?.cancel();
    _gyroscopeSub?.cancel();
    _proximitySub?.cancel();
    _phoneController.dispose();
    super.dispose();
  }

  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Native / Device 能力诊断'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新设备状态',
            onPressed: _fetchDeviceStatus,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildPlatformCard(),
          const SizedBox(height: 16),
          _buildSystemCard(),
          const SizedBox(height: 16),
          _buildDeviceCard(),
          const SizedBox(height: 16),
          _buildSensorsCard(),
        ],
      ),
    );
  }

  Widget _buildPlatformCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.devices, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('原生能力支持矩阵', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusChip(platform: 'Android', supported: true, label: '全套传感器 / 电量 / 截屏 / 振动 / 亮度'),
                _StatusChip(platform: 'iOS', supported: true, label: '传感器 / 截屏通知 / 触觉反馈 / 电量 / 亮度'),
                _StatusChip(platform: 'Desktop / Web', supported: true, label: '主题 / 窗口尺寸 / 内存 / 安全降级'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('系统事件监听 (System Events)', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),

            // Theme & Resize Status
            Row(
              children: [
                Expanded(
                  child: _infoTile(
                    '系统主题 (Theme)',
                    _currentBrightness.name.toUpperCase(),
                    icon: _currentBrightness == Brightness.dark ? Icons.dark_mode : Icons.light_mode,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _infoTile(
                    '窗口尺寸 (Size)',
                    '${_currentWindowSize.width.toInt()} x ${_currentWindowSize.height.toInt()}',
                    icon: Icons.aspect_ratio,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Memory Warning Status
            _infoTile(
              '内存不足告警 (Memory Pressure)',
              _memoryWarningCount > 0
                  ? '触发 $_memoryWarningCount 次 (最后: ${_formatTime(_lastMemoryWarning!)})'
                  : '正常 (未收到内存告警)',
              icon: Icons.memory,
              color: _memoryWarningCount > 0 ? Colors.orange : Colors.green,
            ),
            const SizedBox(height: 12),

            // Screenshot Events
            Text('截屏监听 (onUserCaptureScreen):', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            if (_screenshotEvents.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('暂未检测到截屏事件（在手机上截图即可实时触发）', style: TextStyle(fontSize: 12, color: Colors.grey)),
              )
            else
              Column(
                children: _screenshotEvents
                    .map((event) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              const Icon(Icons.camera_alt, size: 14, color: Colors.blue),
                              const SizedBox(width: 6),
                              Text(event, style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
                            ],
                          ),
                        ))
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.smartphone, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('设备硬件控制 (Device Controls)', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),

            // Battery Info
            Row(
              children: [
                Icon(
                  _batteryInfo?.isCharging == true ? Icons.battery_charging_full : Icons.battery_std,
                  color: Colors.green,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '电池电量: ${_batteryInfo?.level ?? 100}%  (${_batteryInfo?.isCharging == true ? '充电中' : '未充电'})',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '状态: ${_batteryInfo?.status.name ?? 'unknown'}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                OutlinedButton(
                  onPressed: _fetchDeviceStatus,
                  child: const Text('刷新'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Screen Brightness
            Text('屏幕亮度: ${(_screenBrightness * 100).toInt()}%', style: Theme.of(context).textTheme.labelLarge),
            Slider(
              value: _screenBrightness,
              min: 0.0,
              max: 1.0,
              onChanged: (val) {
                setState(() => _screenBrightness = val);
                Native.setScreenBrightness(val);
              },
            ),
            const SizedBox(height: 12),

            // Vibration & Haptic
            Text('振动与触觉反馈 (Vibration & Haptics):', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.vibration, size: 16),
                  label: const Text('轻触 (Light)'),
                  onPressed: () async {
                    await Native.vibrate(HapticFeedbackType.light);
                    setState(() => _vibrateStatus = '触发 Light 触觉反馈');
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.vibration, size: 16),
                  label: const Text('中等 (Medium)'),
                  onPressed: () async {
                    await Native.vibrate(HapticFeedbackType.medium);
                    setState(() => _vibrateStatus = '触发 Medium 触觉反馈');
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.vibration, size: 16),
                  label: const Text('重触 (Heavy)'),
                  onPressed: () async {
                    await Native.vibrate(HapticFeedbackType.heavy);
                    setState(() => _vibrateStatus = '触发 Heavy 触觉反馈');
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.touch_app, size: 16),
                  label: const Text('选择 (Selection)'),
                  onPressed: () async {
                    await Native.vibrate(HapticFeedbackType.selection);
                    setState(() => _vibrateStatus = '触发 Selection 触觉反馈');
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.alarm, size: 16),
                  label: const Text('500ms 振动'),
                  onPressed: () async {
                    await Native.vibrate(HapticFeedbackType.vibrate, 500);
                    setState(() => _vibrateStatus = '触发 500ms 定时振动');
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('执行状态: $_vibrateStatus', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),

            // Phone Call
            Text('拨打电话 (Make Phone Call):', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _phoneController,
                    decoration: const InputDecoration(
                      labelText: '电话号码',
                      hintText: '10086',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => Native.makePhoneCall(_phoneController.text),
                  icon: const Icon(Icons.call),
                  label: const Text('呼叫'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSensorsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sensors, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('运动与环境传感器 (Sensors)', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),

            // Accelerometer
            _sensorSection(
              title: '加速度计 (Accelerometer, ~5次/秒)',
              isListening: _listeningAccelerometer,
              onToggle: _toggleAccelerometer,
              valueText: _accelerometerEvent != null
                  ? 'X: ${_accelerometerEvent!.x.toStringAsFixed(2)}  '
                      'Y: ${_accelerometerEvent!.y.toStringAsFixed(2)}  '
                      'Z: ${_accelerometerEvent!.z.toStringAsFixed(2)} m/s²'
                  : '等待数据...',
            ),
            const SizedBox(height: 16),

            // Gyroscope
            _sensorSection(
              title: '陀螺仪 (Gyroscope)',
              isListening: _listeningGyroscope,
              onToggle: _toggleGyroscope,
              valueText: _gyroscopeEvent != null
                  ? 'X: ${_gyroscopeEvent!.x.toStringAsFixed(2)}  '
                      'Y: ${_gyroscopeEvent!.y.toStringAsFixed(2)}  '
                      'Z: ${_gyroscopeEvent!.z.toStringAsFixed(2)} rad/s'
                  : '等待数据...',
            ),
            const SizedBox(height: 16),

            // Proximity
            _sensorSection(
              title: '距离传感器 (Proximity)',
              isListening: _listeningProximity,
              onToggle: _toggleProximity,
              valueText: _proximityEvent != null
                  ? '${_proximityEvent!.isNear ? '🔴 靠近 (Near)' : '🟢 远离 (Far)'} (距离: ${_proximityEvent!.distance}cm)'
                  : '等待数据...',
            ),
          ],
        ),
      ),
    );
  }

  Widget _sensorSection({
    required String title,
    required bool isListening,
    required void Function(bool) onToggle,
    required String valueText,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Switch(
                value: isListening,
                onChanged: onToggle,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isListening ? valueText : '未开启监听',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: isListening ? Theme.of(context).colorScheme.primary : Colors.grey,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoTile(String label, String value, {IconData? icon, Color? color}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: color ?? Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.platform,
    required this.supported,
    required this.label,
  });

  final String platform;
  final bool supported;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(
        supported ? Icons.check_circle : Icons.cancel,
        color: supported ? Colors.green : Colors.grey,
        size: 16,
      ),
      label: Text('$platform: $label'),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}
