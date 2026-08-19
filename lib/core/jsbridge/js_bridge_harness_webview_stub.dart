import 'package:flutter/material.dart';

import 'js_api_dispatcher.dart';

class JsBridgeHarnessWebView extends StatelessWidget {
  const JsBridgeHarnessWebView({
    required this.url,
    required this.dispatcher,
    super.key,
  });

  final String url;
  final JsApiDispatcher dispatcher;

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Text('当前平台没有可用的内嵌 WebView。请在 Android、iOS 或 macOS 运行 Harness。'),
    ),
  );
}
