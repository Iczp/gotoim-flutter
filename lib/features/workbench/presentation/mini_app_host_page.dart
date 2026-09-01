import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../core/floating_window/floating_window.dart';
import '../application/webview_session.dart';
import '../data/workbench_models.dart';

/// WebView container page for a MiniApp.
///
/// Features:
/// - Branded loading overlay with app icon, spinner, and live progress percentage
///   to prevent blank white screens during initial launch.
/// - Smooth animated fade transition into WebView content.
/// - Title bar with app name and adaptive title updates.
/// - Back navigation (WebView goBack → close task).
/// - Network error page with one-tap retry.
/// - Close button to finish and cleanup the task.
class MiniAppHostPage extends ConsumerStatefulWidget {
  const MiniAppHostPage({
    required this.request,
    this.channel = const MethodChannel('com.gotoim.mini_app'),
    super.key,
  });

  final MiniAppLaunchRequest request;
  final MethodChannel channel;

  @override
  ConsumerState<MiniAppHostPage> createState() => _MiniAppHostPageState();
}

class _MiniAppHostPageState extends ConsumerState<MiniAppHostPage> {
  InAppWebViewController? _webController;
  late final WebViewSession _session;
  bool _isLoading = true;
  double _progress = 0.0;
  String? _error;
  String _title = '';
  bool _canGoBack = false;
  bool _isMinimized = false;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _session = WebViewSessionRegistry.shared.obtain(
      id: '${widget.request.appId}:${widget.request.url}',
      url: widget.request.url,
      title: widget.request.title,
    );
    _title = widget.request.title ?? widget.request.appId;
    _startTimeoutWatchdog();
  }

  void _startTimeoutWatchdog() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && _isLoading && _error == null && _progress < 0.3) {
        setState(() {
          _error = '加载超时，请检查网络连接或服务地址是否可达。';
          _isLoading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    final webController = _webController;
    if (webController != null) _session.detach(webController);
    WebViewSessionRegistry.shared.release(_session.id);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MiniAppHostPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.request.url != oldWidget.request.url) {
      setState(() {
        _isLoading = true;
        _progress = 0.0;
        _error = null;
      });
      _startTimeoutWatchdog();
      _webController?.loadUrl(
        urlRequest: URLRequest(url: WebUri.uri(widget.request.url)),
      );
    }
    if (widget.request.title != null &&
        widget.request.title != oldWidget.request.title) {
      setState(() => _title = widget.request.title!);
    }
  }

  Future<bool> _safeCanGoBack() async {
    if (_webController == null) return false;
    try {
      return await _webController!.canGoBack();
    } catch (_) {
      return false;
    }
  }

  Future<void> _handleBack() async {
    // Priority: WebView can go back → go back. Otherwise close task.
    if (_canGoBack && _webController != null) {
      final canBack = await _safeCanGoBack();
      if (canBack) {
        try {
          await _webController!.goBack();
          return;
        } catch (_) {}
      }
    }
    // At root of MiniApp → close the task.
    await _closeTask();
  }

  Future<void> _closeTask() async {
    try {
      ref.read(floatingWindowManagerProvider).close(_floatingWindowId);
    } catch (_) {}
    try {
      await widget.channel.invokeMethod<void>('closeTask');
    } catch (e) {
      debugPrint('[MiniApp] closeTask error: $e');
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  String get _floatingWindowId => 'webview-session:${_session.id}';

  Future<void> _minimize() async {
    try {
      await widget.channel.invokeMethod<void>('minimizeTask');
    } catch (e) {
      debugPrint('[MiniApp] minimizeTask channel error: $e');
      // If running inside the same Flutter navigator (iOS / Desktop / fallback):
      if (mounted) {
        final title = _title.isEmpty ? widget.request.appId : _title;
        try {
          ref.read(floatingWindowManagerProvider).show(
            id: _floatingWindowId,
            options: const FloatingWindowOptions(
              initialSize: Size(232, 92),
              snapToEdge: true,
              resizable: false,
            ),
            child: _MiniAppRestoreWindow(
              title: title,
              onRestore: () {
                ref.read(floatingWindowManagerProvider).close(_floatingWindowId);
                if (mounted) {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => MiniAppHostPage(
                        request: widget.request,
                        channel: widget.channel,
                      ),
                    ),
                  );
                }
              },
              onClose: _closeTask,
            ),
          );
        } catch (_) {}
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
    }
  }

  void _restore() {
    try {
      ref.read(floatingWindowManagerProvider).close(_floatingWindowId);
    } catch (_) {}
    _session.restore();
    if (mounted) setState(() => _isMinimized = false);
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
          title: Text(_title.isNotEmpty ? _title : widget.request.appId),
          actions: [
            IconButton(
              icon: const Icon(Icons.picture_in_picture_alt_outlined),
              tooltip: '缩小并保持页面',
              onPressed: _isMinimized ? _restore : _minimize,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '刷新',
              onPressed: () {
                setState(() {
                  _error = null;
                  _isLoading = true;
                  _progress = 0.0;
                });
                _startTimeoutWatchdog();
                _webController?.reload();
              },
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: '关闭应用',
              onPressed: _closeTask,
            ),
          ],
          bottom:
              _isLoading && _error == null
                  ? PreferredSize(
                    preferredSize: const Size.fromHeight(2.0),
                    child: LinearProgressIndicator(
                      value: _progress > 0 ? _progress : null,
                      minHeight: 2.0,
                    ),
                  )
                  : null,
        ),
        body: Stack(
          children: [
            // WebView layer
            if (_error == null)
              Offstage(
                offstage: _isMinimized,
                child: InAppWebView(
                  initialUrlRequest: URLRequest(
                    url: WebUri.uri(widget.request.url),
                  ),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    domStorageEnabled: true,
                    useOnLoadResource: false,
                    useShouldOverrideUrlLoading: false,
                    mediaPlaybackRequiresUserGesture: false,
                    transparentBackground: true,
                  ),
                  onWebViewCreated: (controller) {
                    _webController = controller;
                    _session.attach(controller);
                  },
                  onLoadStart: (controller, url) {
                    _session.didStart(url);
                    if (mounted) {
                      setState(() {
                        _isLoading = true;
                        _error = null;
                      });
                    }
                  },
                  onProgressChanged: (controller, progress) {
                    _session.didProgress(progress);
                    if (!mounted) return;
                    final normalizedProgress = progress / 100.0;
                    setState(() {
                      _progress = normalizedProgress;
                      if (progress >= 85) {
                        _isLoading = false;
                        _timeoutTimer?.cancel();
                      }
                    });
                  },
                  onLoadStop: (controller, url) async {
                    await _session.didStop(controller, url);
                    if (!mounted) return;
                    final canGoBack = await _safeCanGoBack();
                    setState(() {
                      _isLoading = false;
                      _progress = 1.0;
                      _canGoBack = canGoBack;
                    });
                    _timeoutTimer?.cancel();
                  },
                  onReceivedError: (controller, request, error) {
                    _session.didFail(error);
                    if (mounted) {
                      setState(() {
                        _isLoading = false;
                        _error = '${error.description} (${error.type})';
                      });
                      _timeoutTimer?.cancel();
                    }
                  },
                  onTitleChanged: (controller, title) {
                    _session.didChangeTitle(title);
                    if (mounted && title != null && title.isNotEmpty) {
                      setState(() => _title = title);
                    }
                  },
                  onUpdateVisitedHistory: (controller, url, isReload) async {
                    await _session.didVisit(controller, url);
                    if (!mounted) return;
                    final canGoBack = await _safeCanGoBack();
                    setState(() => _canGoBack = canGoBack);
                  },

                ),
              ),

            // Loading overlay with smooth fade out
            if (_error == null && !_isMinimized)
              IgnorePointer(
                ignoring: !_isLoading,
                child: AnimatedOpacity(
                  opacity: _isLoading ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: _MiniAppLoadingOverlay(
                    title: _title.isNotEmpty ? _title : widget.request.appId,
                    url: widget.request.url,
                    progress: _progress,
                  ),
                ),
              ),

            // Error View
            if (_error != null)
              _ErrorView(
                error: _error!,
                url: widget.request.url.toString(),
                onRetry: () {
                  setState(() {
                    _error = null;
                    _isLoading = true;
                    _progress = 0.0;
                  });
                  _startTimeoutWatchdog();
                  _webController?.reload();
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _MiniAppRestoreWindow extends StatelessWidget {
  const _MiniAppRestoreWindow({
    required this.title,
    required this.onRestore,
    required this.onClose,
  });

  final String title;
  final VoidCallback onRestore;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.web_outlined),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            tooltip: '恢复 WebView',
            onPressed: onRestore,
            icon: const Icon(Icons.open_in_full),
          ),
          IconButton(
            tooltip: '关闭 WebView',
            onPressed: onClose,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    ),
  );
}

/// Rich loading overlay preventing white screen during MiniApp engine/network initialization.
class _MiniAppLoadingOverlay extends StatelessWidget {
  const _MiniAppLoadingOverlay({
    required this.title,
    required this.url,
    required this.progress,
  });

  final String title;
  final Uri url;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final initial = title.isNotEmpty ? title[0].toUpperCase() : 'M';
    final percent = (progress * 100).toInt();

    return Container(
      color: theme.scaffoldBackgroundColor,
      width: double.infinity,
      height: double.infinity,
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // App Avatar
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [colorScheme.primary, colorScheme.primaryContainer],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Title
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),

              // Subtitle Domain
              Text(
                url.host.isNotEmpty ? url.host : url.toString(),
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 32),

              // Spinner & Progress
              SizedBox(
                width: 44,
                height: 44,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: progress > 0 ? progress : null,
                      strokeWidth: 3.5,
                    ),
                    if (progress > 0)
                      Text(
                        '$percent%',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Text(
                progress > 0 ? '正在加载资源 ($percent%)...' : '正在启动应用容器...',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
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
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      width: double.infinity,
      height: double.infinity,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                '页面加载失败',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                url,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  error,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重新加载'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
