import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../app/application_providers.dart';
import '../../../core/config/app_environment.dart';
import '../../../core/jsbridge/js_bridge_harness_webview.dart';
import '../../../core/platform/platform_facade.dart';

class JsBridgeHarnessPage extends ConsumerStatefulWidget {
  const JsBridgeHarnessPage({super.key});

  @override
  ConsumerState<JsBridgeHarnessPage> createState() =>
      _JsBridgeHarnessPageState();
}

class _JsBridgeHarnessPageState extends ConsumerState<JsBridgeHarnessPage> {
  late final TextEditingController _urlController;
  late String _loadedUrl;
  String? _inputError;
  String? _loadError;
  String? _pageStatus;
  int _progress = 0;
  String _hostPingResult = '尚未发起 Flutter → H5 主动调用。';
  StreamSubscription? _bridgeEventsSubscription;
  final StreamController<Map<String, Object?>> _hostEvents =
      StreamController<Map<String, Object?>>.broadcast();

  @override
  void initState() {
    super.initState();
    final configuredUrl = ref.read(appEnvironmentProvider).jsBridgeHarnessUrl;
    _loadedUrl =
        configuredUrl.trim().isEmpty
            ? _fallbackHarnessUrl(ref.read(platformFacadeProvider).kind)
            : configuredUrl.trim();
    _urlController = TextEditingController(text: _loadedUrl);
    _pageStatus = '准备请求 $_loadedUrl';
    _bridgeEventsSubscription = ref.read(jsApiDispatcherProvider).events.listen(
      (event) {
        if (!mounted || event.name != 'diagnostics.hostPingResult') return;
        setState(() {
          _hostPingResult = const JsonEncoder.withIndent(
            '  ',
          ).convert(event.toJson());
        });
      },
    );
  }

  @override
  void dispose() {
    _bridgeEventsSubscription?.cancel();
    _urlController.dispose();
    _hostEvents.close();
    super.dispose();
  }

  void _load() {
    final value = _urlController.text.trim();
    final uri = Uri.tryParse(value);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      setState(() => _inputError = '请输入 http 或 https 地址。');
      return;
    }
    setState(() {
      _inputError = null;
      _loadError = null;
      _pageStatus = '正在请求 $value';
      _progress = 0;
      _loadedUrl = value;
    });
  }

  String _fallbackHarnessUrl(PlatformKind platform) {
    return platform == PlatformKind.android
        ? 'http://10.0.2.2:4173'
        : 'http://127.0.0.1:4173';
  }

  void _sendHostPing() {
    final pingId = DateTime.now().toUtc().toIso8601String();
    _hostEvents.add(<String, Object?>{
      'event': 'host.command',
      'data': <String, Object?>{
        'name': 'harness.ping',
        'pingId': pingId,
        'sentAt': pingId,
      },
    });
    setState(() {
      _pageStatus = 'Flutter 已主动发送 harness.ping 给网页，等待 H5 回执。';
      _hostPingResult = '等待 H5 回执。pingId: $pingId';
    });
  }

  void _configureH5Harness() {
    _hostEvents.add(<String, Object?>{
      'event': 'harness.config',
      'data': <String, Object?>{
        'uploadUrl': ref.read(appEnvironmentProvider).jsBridgeUploadUrl,
      },
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(
        body: Center(child: Text('JS Bridge Harness 仅在 Debug 模式可用。')),
      );
    }
    final platform = ref.read(platformFacadeProvider).kind;
    final supported =
        platform == PlatformKind.android ||
        platform == PlatformKind.ios ||
        platform == PlatformKind.macos ||
        platform == PlatformKind.windows;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: const Text('JS Bridge Harness')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    keyboardType: TextInputType.url,
                    onSubmitted: (_) => _load(),
                    decoration: InputDecoration(
                      labelText: 'Harness 地址',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      errorText: _inputError,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 64,
                  child: FilledButton(
                    onPressed: _load,
                    child: const Text('加载'),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 140,
                  child: OutlinedButton(
                    onPressed: supported ? _sendHostPing : null,
                    child: const Text('Flutter → H5 Ping'),
                  ),
                ),
              ],
            ),
          ),
          _LoadFeedback(
            progress: _progress,
            status: _pageStatus,
            error: _loadError,
          ),
          _HostPingResult(value: _hostPingResult),
          if (!supported)
            const Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    '当前平台没有可用的 WebView 测试宿主。请使用 Android、iOS、macOS 或 Windows，或改用 JSON 模拟诊断页。',
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: JsBridgeHarnessWebView(
                key: ValueKey<String>(_loadedUrl),
                url: _loadedUrl,
                dispatcher: ref.read(jsApiDispatcherProvider),
                onProgress: (value) {
                  if (mounted) setState(() => _progress = value);
                },
                onPageStarted: (url) {
                  if (!mounted) return;
                  setState(() {
                    _loadError = null;
                    _pageStatus = '正在加载 $url';
                  });
                },
                onPageFinished: (url) {
                  if (!mounted) return;
                  setState(() {
                    _progress = 100;
                    _pageStatus = '已加载 $url';
                  });
                  _configureH5Harness();
                },
                onError: (message) {
                  if (mounted) setState(() => _loadError = message);
                },
                onNavigationBlocked: (message) {
                  if (mounted) setState(() => _pageStatus = message);
                },
                hostEvents: _hostEvents.stream,
              ),
            ),
        ],
      ),
    );
  }
}

class _HostPingResult extends StatelessWidget {
  const _HostPingResult({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 70),
                  child: SingleChildScrollView(
                    child: SelectionArea(
                      child: Text(
                        'Flutter → H5 Ping 回执\n$value',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: '复制 Ping 回执',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: value));
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('Ping 回执已复制')));
                  }
                },
                icon: const Icon(Icons.copy_outlined),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadFeedback extends StatelessWidget {
  const _LoadFeedback({
    required this.progress,
    required this.status,
    required this.error,
  });

  final int progress;
  final String? status;
  final String? error;

  @override
  Widget build(BuildContext context) {
    if (error == null && status == null) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color:
              error == null
                  ? colorScheme.surfaceContainerHighest
                  : colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (error == null && progress < 100) ...[
                LinearProgressIndicator(
                  value: progress == 0 ? null : progress / 100,
                ),
                const SizedBox(height: 8),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SelectionArea(
                      child: Text(
                        error ?? status!,
                        style: TextStyle(
                          color:
                              error == null
                                  ? null
                                  : colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '复制信息',
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: error ?? status!),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(const SnackBar(content: Text('信息已复制')));
                      }
                    },
                    icon: const Icon(Icons.copy_outlined),
                  ),
                ],
              ),
              if (error != null) ...[
                const SizedBox(height: 4),
                Text(
                  '请检查设备与电脑是否在同一局域网、地址端口是否可达，以及应用的网络权限。',
                  style: TextStyle(color: colorScheme.onErrorContainer),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
