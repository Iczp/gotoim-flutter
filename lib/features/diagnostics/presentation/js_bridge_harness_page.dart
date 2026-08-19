import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/application_providers.dart';
import '../../../core/jsbridge/js_bridge_harness_webview.dart';
import '../../../core/platform/platform_contract.dart';
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

  @override
  void initState() {
    super.initState();
    _loadedUrl = 'http://10.0.2.2:4173';
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
      _loadedUrl = value;
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
              ),
            ),
        ],
      ),
    );
  }
}
