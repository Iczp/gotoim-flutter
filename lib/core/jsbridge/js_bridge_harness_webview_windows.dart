part of 'js_bridge_harness_webview_io.dart';

/// Windows WebView2 host for the JS Bridge harness.
///
/// This is intentionally separated from the mobile adapter because the
/// official [webview_flutter] plugin does not provide a Windows implementation.
class _WindowsHarnessWebViewState extends State<JsBridgeHarnessWebView> {
  final WebviewController _controller = WebviewController();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  late final JsBridgeSession _session;
  Timer? _loadTimeout;
  StreamSubscription<Map<String, Object?>>? _hostEventsSubscription;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _session = JsBridgeSession(
      dispatcher: widget.dispatcher,
      transport: _WindowsWebViewTransport(_controller),
    )..start();
    _hostEventsSubscription = widget.hostEvents?.listen(_postHostEvent);
    unawaited(_initialize());
  }

  @override
  void didUpdateWidget(covariant JsBridgeHarnessWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_initialized && oldWidget.url != widget.url) {
      unawaited(_load(widget.url));
    }
  }

  Future<void> _initialize() async {
    try {
      _subscriptions.add(
        _controller.webMessage.listen((message) {
          final raw = message is String ? message : jsonEncode(message);
          unawaited(_handleBridgeMessage(raw));
        }),
      );
      _subscriptions.add(
        _controller.loadingState.listen((state) {
          if (state == LoadingState.navigationCompleted) {
            _loadTimeout?.cancel();
            widget.onProgress?.call(100);
            widget.onPageFinished?.call(widget.url);
          }
        }),
      );
      _subscriptions.add(
        _controller.onLoadError.listen((status) {
          _loadTimeout?.cancel();
          widget.onError?.call('Windows WebView2 加载失败：$status');
        }),
      );

      await _controller.initialize();
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      await _controller.setDefaultContextMenusEnabled(true);
      if (!mounted) return;
      setState(() => _initialized = true);
      await _load(widget.url);
    } catch (error) {
      widget.onError?.call(
        'Windows WebView2 初始化失败：$error\n'
        '请确认已安装 Microsoft Edge WebView2 Runtime。',
      );
    }
  }

  Future<void> _load(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      widget.onError?.call('无效的 Harness 地址：$url');
      return;
    }
    _beginLoadTimeout(url);
    widget.onProgress?.call(5);
    widget.onPageStarted?.call(url);
    try {
      await _controller.loadUrl(url);
    } catch (error) {
      _loadTimeout?.cancel();
      widget.onError?.call('Windows WebView2 无法发起网页加载：$error');
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
      widget.onError?.call('Windows JS Bridge 消息处理失败：$error');
    }
  }

  Future<void> _postHostEvent(Map<String, Object?> event) async {
    try {
      await _controller.postWebMessage(jsonEncode(event));
    } catch (error) {
      widget.onError?.call('Flutter 主动调用网页失败：$error');
    }
  }

  @override
  void dispose() {
    _loadTimeout?.cancel();
    _hostEventsSubscription?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_session.dispose());
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Webview(_controller);
  }
}

class _WindowsWebViewTransport implements JsBridgeTransport {
  const _WindowsWebViewTransport(this._controller);

  final WebviewController _controller;

  @override
  Future<void> postMessage(String message) =>
      _controller.postWebMessage(message);
}
