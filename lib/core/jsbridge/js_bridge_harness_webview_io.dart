import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

import 'js_api_dispatcher.dart';
import 'js_bridge_session.dart';

part 'js_bridge_harness_webview_windows.dart';

/// Debug-only WebView host for the standalone JS Bridge harness.
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
    this.onSelectNativeFiles,
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

  /// Handles a plain H5 <input type="file"> request on Android.
  final Future<List<String>> Function(bool allowMultiple)? onSelectNativeFiles;

  @override
  State<JsBridgeHarnessWebView> createState() => _createHarnessState(); // ignore: no_logic_in_create_state

  State<JsBridgeHarnessWebView> _createHarnessState() =>
      Platform.isWindows
          ? _WindowsHarnessWebViewState()
          : _JsBridgeHarnessWebViewState();
}

class _JsBridgeHarnessWebViewState extends State<JsBridgeHarnessWebView> {
  late final WebViewController _controller;
  late final JsBridgeSession _session;
  Timer? _loadTimeout;
  StreamSubscription<Map<String, Object?>>? _hostEventsSubscription;

  @override
  void initState() {
    super.initState();
    _controller =
        WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setNavigationDelegate(
            NavigationDelegate(
              onProgress: (progress) => widget.onProgress?.call(progress),
              onPageStarted: (url) {
                _beginLoadTimeout(url);
                widget.onPageStarted?.call(url);
              },
              onPageFinished: (url) {
                _loadTimeout?.cancel();
                widget.onPageFinished?.call(url);
              },
              onWebResourceError: (error) {
                _loadTimeout?.cancel();
                final url = error.url?.isEmpty ?? true ? '' : '\n${error.url}';
                widget.onError?.call(
                  '网页加载失败 (${error.errorCode})：${error.description}$url',
                );
              },
              onNavigationRequest:
                  (request) => _navigationDecision(request.url),
            ),
          )
          ..addJavaScriptChannel(
            'GotoIMBridge',
            onMessageReceived: (message) {
              _handleBridgeMessage(message.message);
            },
          );
    final platformController = _controller.platform;
    if (platformController is AndroidWebViewController) {
      platformController.setOnShowFileSelector((params) async {
        final callback = widget.onSelectNativeFiles;
        if (callback == null) return const <String>[];
        try {
          return await callback(params.mode == FileSelectorMode.openMultiple);
        } catch (error) {
          widget.onError?.call('网页文件选择失败：$error');
          return const <String>[];
        }
      });
    }
    _session = JsBridgeSession(
      dispatcher: widget.dispatcher,
      transport: _WebViewTransport(_controller),
    )..start();
    _hostEventsSubscription = widget.hostEvents?.listen(_postHostEvent);
    _load(widget.url);
  }

  @override
  void didUpdateWidget(covariant JsBridgeHarnessWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _load(widget.url);
  }

  @override
  void dispose() {
    _loadTimeout?.cancel();
    _hostEventsSubscription?.cancel();
    _session.dispose();
    super.dispose();
  }

  void _load(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme) {
      widget.onError?.call('无效的 Harness 地址：$value');
      return;
    }
    _beginLoadTimeout(value);
    _controller.loadRequest(uri).catchError((Object error) {
      _loadTimeout?.cancel();
      widget.onError?.call('无法发起网页加载：$error');
    });
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

  Future<void> _postHostEvent(Map<String, Object?> event) async {
    try {
      await _controller.runJavaScript(
        'window.GotoImHarness?.receiveFromHost(${jsonEncode(event)});',
      );
    } catch (error) {
      widget.onError?.call('Flutter 主动调用网页失败：$error');
    }
  }

  NavigationDecision _navigationDecision(String requestedUrl) {
    final requested = Uri.tryParse(requestedUrl);
    final harness = Uri.tryParse(widget.url);
    if (requested == null || harness == null) {
      widget.onNavigationBlocked?.call('已拦截无效跳转：$requestedUrl');
      return NavigationDecision.prevent;
    }
    final sameOrigin =
        requested.scheme == harness.scheme &&
        requested.host == harness.host &&
        requested.port == harness.port;
    if (sameOrigin || requestedUrl == 'about:blank') {
      return NavigationDecision.navigate;
    }
    widget.onNavigationBlocked?.call('已拦截跨域跳转：$requestedUrl');
    return NavigationDecision.prevent;
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}

class _WebViewTransport implements JsBridgeTransport {
  const _WebViewTransport(this._controller);

  final WebViewController _controller;

  @override
  Future<void> postMessage(String message) => _controller.runJavaScript(
    'window.GotoImHarness?.receiveFromHost(${jsonEncode(message)});',
  );
}
