import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'js_api_dispatcher.dart';
import 'js_bridge_session.dart';

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
    super.key,
  });

  final String url;
  final JsApiDispatcher dispatcher;
  final ValueChanged<int>? onProgress;
  final ValueChanged<String>? onPageStarted;
  final ValueChanged<String>? onPageFinished;
  final ValueChanged<String>? onError;
  final ValueChanged<String>? onNavigationBlocked;

  @override
  State<JsBridgeHarnessWebView> createState() => _JsBridgeHarnessWebViewState();
}

class _JsBridgeHarnessWebViewState extends State<JsBridgeHarnessWebView> {
  late final WebViewController _controller;
  late final JsBridgeSession _session;

  @override
  void initState() {
    super.initState();
    _controller =
        WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setNavigationDelegate(
            NavigationDelegate(
              onProgress: widget.onProgress,
              onPageStarted: widget.onPageStarted,
              onPageFinished: widget.onPageFinished,
              onWebResourceError: (error) {
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
    _session = JsBridgeSession(
      dispatcher: widget.dispatcher,
      transport: _WebViewTransport(_controller),
    )..start();
    _load(widget.url);
  }

  @override
  void didUpdateWidget(covariant JsBridgeHarnessWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _load(widget.url);
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  void _load(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme) {
      widget.onError?.call('无效的 Harness 地址：$value');
      return;
    }
    _controller.loadRequest(uri).catchError((Object error) {
      widget.onError?.call('无法发起网页加载：$error');
    });
  }

  Future<void> _handleBridgeMessage(String message) async {
    try {
      await _session.handleIncoming(message);
    } catch (error) {
      widget.onError?.call('JS Bridge 消息处理失败：$error');
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
