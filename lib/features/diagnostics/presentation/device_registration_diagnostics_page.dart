import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/application_providers.dart';
import '../../../core/device/browser_fingerprint.dart';
import '../../../core/device/client_device_context.dart';
import '../../../core/config/app_environment.dart';
import '../../../core/native/native.dart';
import '../../../core/logging/log_sanitizer.dart';

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

  Future<void> _inspectFingerprint() async {
    await _run(() async {
      final nativeId = await Native.device.getPermanentDeviceId();
      final webFingerprint = await getBrowserFingerprint();
      final currentContext = ref.read(clientDeviceContextProvider);
      return <String, Object?>{
        'currentContextDeviceId': currentContext.deviceId,
        'currentPlatform': currentContext.platform,
        'nativeHardwareId': nativeId ?? '当前平台不支持或未返回',
        'webBrowserFingerprint': webFingerprint ?? '非Web环境或未生成',
        'isPermanentStrategyActive': true,
        'persistenceMechanism': {
          'android':
              'Widevine MediaDrm PROPERTY_DEVICE_UNIQUE_ID (fallback: ANDROID_ID)',
          'ios':
              'Keychain (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly) + IDFV',
          'windows': 'MachineGuid (Registry Cryptography)',
          'macOS': 'IOPlatformUUID (System GUID)',
          'linux': 'machine-id (/etc/machine-id)',
          'web':
              'Canvas 2D + WebGL RenderInfo + Navigator + Screen + Timezone Fingerprint',
        },
      };
    });
  }

  Future<void> _collect() async {
    await _run(
      () async => <String, Object?>{
        'endpoint': ref.read(appEnvironmentProvider).deviceRegistrationApiPath,
        'payload': await ref
            .read(deviceRegistrationApiProvider)
            .collectRequestPayload(name: _name.text),
      },
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
                'data': LogSanitizer.sanitize(value),
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
          Text(
            'POST ${ref.watch(appEnvironmentProvider).deviceRegistrationApiPath}；使用独立 client_credentials Token。客户端设备标识作为注册依据，注册与登录互不等待。',
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
              OutlinedButton.icon(
                onPressed: _working ? null : _inspectFingerprint,
                icon: const Icon(Icons.fingerprint),
                label: const Text('查看硬件/浏览器持久指纹'),
              ),
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
