import 'package:flutter/material.dart';

import 'js_api_dispatcher.dart';

class JsBridgeHarnessWebView extends StatelessWidget {
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
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Text('当前平台没有可用的内嵌 WebView。请在 Android、iOS 或 macOS 运行 Harness。'),
    ),
  );
}
