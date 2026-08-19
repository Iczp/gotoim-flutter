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
    super.key,
  });

  final String url;
  final JsApiDispatcher dispatcher;

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
              onNavigationRequest:
                  (request) => _navigationDecision(request.url),
            ),
          )
          ..addJavaScriptChannel(
            'GotoIMBridge',
            onMessageReceived: (message) {
              _session.handleIncoming(message.message);
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
    if (uri == null || !uri.hasScheme) return;
    _controller.loadRequest(uri);
  }

  NavigationDecision _navigationDecision(String requestedUrl) {
    final requested = Uri.tryParse(requestedUrl);
    final harness = Uri.tryParse(widget.url);
    if (requested == null || harness == null) return NavigationDecision.prevent;
    final sameOrigin =
        requested.scheme == harness.scheme &&
        requested.host == harness.host &&
        requested.port == harness.port;
    return sameOrigin || requestedUrl == 'about:blank'
        ? NavigationDecision.navigate
        : NavigationDecision.prevent;
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
