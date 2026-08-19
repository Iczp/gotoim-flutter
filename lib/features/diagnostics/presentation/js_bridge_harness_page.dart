import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  @override
  void initState() {
    super.initState();
    final configuredUrl = ref.read(appEnvironmentProvider).jsBridgeHarnessUrl;
    _loadedUrl = configuredUrl.trim().isEmpty
        ? _fallbackHarnessUrl(ref.read(platformFacadeProvider).kind)
        : configuredUrl.trim();
    _urlController = TextEditingController(text: _loadedUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
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
        platform == PlatformKind.macos;
    return Scaffold(
      appBar: AppBar(title: const Text('JS Bridge Harness')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    keyboardType: TextInputType.url,
                    onSubmitted: (_) => _load(),
                    decoration: InputDecoration(
                      labelText: 'Harness 地址',
                      helperText:
                          platform == PlatformKind.android
                              ? 'Android 模拟器默认 10.0.2.2；真机请填电脑局域网 IP。'
                              : '本机服务可填 http://127.0.0.1:4173。',
                      errorText: _inputError,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _load, child: const Text('加载')),
              ],
            ),
          ),
          _LoadFeedback(
            progress: _progress,
            status: _pageStatus,
            error: _loadError,
          ),
          if (!supported)
            const Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    '官方 WebView 宿主当前仅在 Android、iOS、macOS 启用。Windows/Web 请使用诊断页的 JSON 模拟测试。',
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
                },
                onError: (message) {
                  if (mounted) setState(() => _loadError = message);
                },
                onNavigationBlocked: (message) {
                  if (mounted) setState(() => _pageStatus = message);
                },
              ),
            ),
        ],
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
          color: error == null
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
                LinearProgressIndicator(value: progress == 0 ? null : progress / 100),
                const SizedBox(height: 8),
              ],
              Text(
                error ?? status!,
                style: TextStyle(
                  color: error == null ? null : colorScheme.onErrorContainer,
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 4),
                Text(
                  '请检查手机与电脑是否在同一局域网、地址端口是否可达，以及 Android Debug 包的网络权限。',
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
