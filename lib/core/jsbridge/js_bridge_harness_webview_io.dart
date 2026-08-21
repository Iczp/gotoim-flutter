import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';

import 'js_api_dispatcher.dart';
import 'js_bridge_session.dart';

/// Debug-only WebView host for the standalone JS Bridge harness.
///
/// [flutter_inappwebview] supplies the same host widget and controller contract
/// on Android, iOS, macOS, and Windows. The H5 page talks to the native side
/// through the `GotoIMBridge` JavaScript handler.
class JsBridgeHarnessWebView extends StatefulWidget {
  const JsBridgeHarnessWebView({
    required this.url,
    required this.dispatcher,
    this.onProgress,
    this.onPageStarted,
    this.onPageFinished,
    this.onError,
    this.onNavigationBlocked,
    this.hostEvents,
    super.key,
  });

  final String url;
  final JsApiDispatcher dispatcher;
  final ValueChanged<int>? onProgress;
  final ValueChanged<String>? onPageStarted;
  final ValueChanged<String>? onPageFinished;
  final ValueChanged<String>? onError;
  final ValueChanged<String>? onNavigationBlocked;

  /// Messages initiated by Flutter and delivered to the loaded H5 page.
  final Stream<Map<String, Object?>>? hostEvents;

  @override
  State<JsBridgeHarnessWebView> createState() => _JsBridgeHarnessWebViewState();
}

class _JsBridgeHarnessWebViewState extends State<JsBridgeHarnessWebView> {
  InAppWebViewController? _controller;
  late final JsBridgeSession _session;
  Timer? _loadTimeout;
  StreamSubscription<Map<String, Object?>>? _hostEventsSubscription;
  WebViewEnvironment? _windowsEnvironment;
  String? _initializationError;
  bool _ready = !Platform.isWindows;

  @override
  void initState() {
    super.initState();
    _session = JsBridgeSession(
      dispatcher: widget.dispatcher,
      transport: _InAppWebViewTransport(_postSessionMessage),
    )..start();
    _hostEventsSubscription = widget.hostEvents?.listen(_postHostEvent);
    if (Platform.isWindows) {
      unawaited(_prepareWindowsEnvironment());
    }
  }

  @override
  void didUpdateWidget(covariant JsBridgeHarnessWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url && _controller != null) {
      unawaited(_load(widget.url));
    }
  }

  @override
  void dispose() {
    _loadTimeout?.cancel();
    _hostEventsSubscription?.cancel();
    unawaited(_session.dispose());
    super.dispose();
  }

  Future<void> _prepareWindowsEnvironment() async {
    try {
      final availableVersion = await WebViewEnvironment.getAvailableVersion();
      if (availableVersion == null) {
        throw StateError('未检测到 Microsoft Edge WebView2 Runtime。');
      }
      final supportDirectory = await getApplicationSupportDirectory();
      _windowsEnvironment = await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(
          userDataFolder:
              '${supportDirectory.path}${Platform.pathSeparator}js_bridge_harness_webview2',
        ),
      );
      if (mounted) setState(() => _ready = true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _initializationError =
              'Windows WebView2 初始化失败：$error\n'
              '请确认已安装 Microsoft Edge WebView2 Runtime。';
        });
      }
    }
  }

  Future<void> _load(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      widget.onError?.call('无效的 Harness 地址：$value');
      return;
    }
    final controller = _controller;
    if (controller == null) return;
    _beginLoadTimeout(value);
    try {
      await controller.loadUrl(urlRequest: URLRequest(url: WebUri(value)));
    } catch (error) {
      _loadTimeout?.cancel();
      widget.onError?.call('无法发起网页加载：$error');
    }
  }

  void _beginLoadTimeout(String url) {
    _loadTimeout?.cancel();
    _loadTimeout = Timer(const Duration(seconds: 15), () {
      widget.onError?.call(
        '等待网页加载超时（15 秒）：$url\n'
        '请检查地址、端口、局域网连接和服务器防火墙。',
      );
    });
  }

  Future<void> _handleBridgeMessage(String message) async {
    try {
      await _session.handleIncoming(message);
    } catch (error) {
      widget.onError?.call('JS Bridge 消息处理失败：$error');
    }
  }

  Future<void> _postHostEvent(Map<String, Object?> event) => _postToPage(event);

  Future<void> _postSessionMessage(String message) => _postToPage(message);

  Future<void> _postToPage(Object message) async {
    final controller = _controller;
    if (controller == null) {
      throw StateError('WebView 尚未创建，无法向 H5 发送消息。');
    }
    try {
      await controller.evaluateJavascript(
        source:
            'window.GotoImHarness?.receiveFromHost(${jsonEncode(message)});',
      );
    } catch (error) {
      widget.onError?.call('Flutter 主动调用网页失败：$error');
    }
  }

  NavigationActionPolicy _navigationDecision(String requestedUrl) {
    final requested = Uri.tryParse(requestedUrl);
    final harness = Uri.tryParse(widget.url);
    if (requested == null || harness == null) {
      widget.onNavigationBlocked?.call('已拦截无效跳转：$requestedUrl');
      return NavigationActionPolicy.CANCEL;
    }
    final sameOrigin =
        requested.scheme == harness.scheme &&
        requested.host == harness.host &&
        requested.port == harness.port;
    if (sameOrigin || requestedUrl == 'about:blank') {
      return NavigationActionPolicy.ALLOW;
    }
    widget.onNavigationBlocked?.call('已拦截跨域跳转：$requestedUrl');
    return NavigationActionPolicy.CANCEL;
  }

  @override
  Widget build(BuildContext context) {
    if (_initializationError case final error?) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SelectionArea(child: Text(error)),
        ),
      );
    }
    if (!_ready) return const Center(child: CircularProgressIndicator());
    return InAppWebView(
      webViewEnvironment: _windowsEnvironment,
      initialUrlRequest: URLRequest(url: WebUri(widget.url)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        javaScriptBridgeEnabled: true,
        useShouldOverrideUrlLoading: true,
        supportMultipleWindows: false,
      ),
      onWebViewCreated: (controller) {
        _controller = controller;
        controller.addJavaScriptHandler(
          handlerName: 'GotoIMBridge',
          callback: (arguments) async {
            final raw = arguments.isEmpty ? null : arguments.first;
            if (raw is! String) {
              widget.onError?.call('JS Bridge 消息必须是字符串 JSON。');
              return null;
            }
            await _handleBridgeMessage(raw);
            return null;
          },
        );
      },
      onLoadStart: (_, url) {
        final value = url?.toString() ?? widget.url;
        _beginLoadTimeout(value);
        widget.onPageStarted?.call(value);
      },
      onLoadStop: (_, url) {
        _loadTimeout?.cancel();
        widget.onProgress?.call(100);
        widget.onPageFinished?.call(url?.toString() ?? widget.url);
      },
      onProgressChanged: (_, progress) => widget.onProgress?.call(progress),
      onReceivedError: (_, request, error) {
        _loadTimeout?.cancel();
        final url = request.url.toString();
        widget.onError?.call(
          '网页加载失败 (${error.type})：${error.description}'
          '${url.isEmpty ? '' : '\n$url'}',
        );
      },
      shouldOverrideUrlLoading:
          (_, action) async =>
              _navigationDecision(action.request.url?.toString() ?? ''),
    );
  }
}

class _InAppWebViewTransport implements JsBridgeTransport {
  const _InAppWebViewTransport(this._postMessage);

  final Future<void> Function(String message) _postMessage;

  @override
  Future<void> postMessage(String message) => _postMessage(message);
}
