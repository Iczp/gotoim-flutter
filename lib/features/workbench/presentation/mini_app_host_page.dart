import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../data/workbench_models.dart';

/// WebView container page for a MiniApp.
///
/// Handles:
/// - Title bar with app name
/// - Back navigation (WebView goBack → Navigator pop → close task)
/// - Loading indicator
/// - Error page with retry
/// - Close button to finish the task
class MiniAppHostPage extends StatefulWidget {
  const MiniAppHostPage({
    required this.request,
    this.channel = const MethodChannel('com.gotoim.mini_app'),
    super.key,
  });

  final MiniAppLaunchRequest request;
  final MethodChannel channel;

  @override
  State<MiniAppHostPage> createState() => _MiniAppHostPageState();
}

class _MiniAppHostPageState extends State<MiniAppHostPage> {
  InAppWebViewController? _webController;
  bool _isLoading = true;
  String? _error;
  String _title = '';
  bool _canGoBack = false;

  @override
  void initState() {
    super.initState();
    _title = widget.request.title ?? widget.request.appId;
  }

  @override
  void didUpdateWidget(covariant MiniAppHostPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If we receive a new URL via onNewIntent, navigate the WebView.
    if (widget.request.url != oldWidget.request.url) {
      _webController?.loadUrl(
        urlRequest: URLRequest(url: WebUri.uri(widget.request.url)),
      );
    }
    if (widget.request.title != null &&
        widget.request.title != oldWidget.request.title) {
      setState(() => _title = widget.request.title!);
    }
  }

  Future<void> _handleBack() async {
    // Priority: WebView can go back → go back. Otherwise close task.
    if (_canGoBack && _webController != null) {
      await _webController!.goBack();
      return;
    }
    // At root of MiniApp → close the task.
    await _closeTask();
  }

  Future<void> _closeTask() async {
    try {
      await widget.channel.invokeMethod<void>('closeTask');
    } catch (e) {
      debugPrint('[MiniApp] closeTask error: $e');
      // Fallback: try Navigator pop.
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: '返回',
            onPressed: _handleBack,
          ),
          title: Text(_title),
          actions: [
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: '关闭',
              onPressed: _closeTask,
            ),
          ],
        ),
        body: Stack(
          children: [
            if (_error != null)
              _ErrorView(
                error: _error!,
                url: widget.request.url.toString(),
                onRetry: () {
                  setState(() => _error = null);
                  _webController?.reload();
                },
              )
            else
              InAppWebView(
                initialUrlRequest: URLRequest(
                  url: WebUri.uri(widget.request.url),
                ),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  useOnLoadResource: false,
                  useShouldOverrideUrlLoading: false,
                  mediaPlaybackRequiresUserGesture: false,
                ),
                onWebViewCreated: (controller) {
                  _webController = controller;
                },
                onLoadStart: (controller, url) {
                  if (mounted) setState(() => _isLoading = true);
                },
                onLoadStop: (controller, url) async {
                  if (!mounted) return;
                  final canGoBack = await controller.canGoBack();
                  setState(() {
                    _isLoading = false;
                    _canGoBack = canGoBack;
                  });
                },
                onReceivedError: (controller, request, error) {
                  if (mounted) {
                    setState(() {
                      _isLoading = false;
                      _error = '${error.description} (${error.type})';
                    });
                  }
                },
                onTitleChanged: (controller, title) {
                  if (mounted && title != null && title.isNotEmpty) {
                    setState(() => _title = title);
                  }
                },
                onUpdateVisitedHistory: (controller, url, isReload) async {
                  if (!mounted) return;
                  final canGoBack = await controller.canGoBack();
                  setState(() => _canGoBack = canGoBack);
                },
              ),
            if (_isLoading && _error == null)
              const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.error,
    required this.url,
    required this.onRetry,
  });

  final String error;
  final String url;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              '页面加载失败',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              url,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
