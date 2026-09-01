import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Stateful business session for one MiniApp WebView.
///
/// It owns navigation/bridge metadata, not a Flutter widget. A PlatformView
/// must remain hosted by a platform-verified WebView host; callers must not
/// move an [InAppWebView] between a page and FloatingWindow as if it were a
/// normal Flutter child.
class WebViewSession extends ChangeNotifier {
  WebViewSession({required this.id, required Uri initialUrl, String? title})
    : _currentUrl = initialUrl,
      _title = title ?? '',
      _history = <Uri>[initialUrl];

  final String id;
  InAppWebViewController? _controller;
  Uri _currentUrl;
  String _title;
  bool _loading = true;
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _minimized = false;
  int _cookieCount = 0;
  final List<Uri> _history;
  WebViewJsBridgeStatus _jsBridgeStatus = WebViewJsBridgeStatus.unbound;
  int _jsBridgeRequestCount = 0;
  String? _error;

  InAppWebViewController? get controller => _controller;
  Uri get currentUrl => _currentUrl;
  String get title => _title;
  bool get loading => _loading;
  bool get canGoBack => _canGoBack;
  bool get canGoForward => _canGoForward;
  bool get minimized => _minimized;
  int get cookieCount => _cookieCount;
  List<Uri> get history => List<Uri>.unmodifiable(_history);
  WebViewJsBridgeStatus get jsBridgeStatus => _jsBridgeStatus;
  int get jsBridgeRequestCount => _jsBridgeRequestCount;
  String? get error => _error;

  void attach(InAppWebViewController controller) {
    _controller = controller;
    notifyListeners();
  }

  void detach(InAppWebViewController controller) {
    if (!identical(_controller, controller)) return;
    _controller = null;
    notifyListeners();
  }

  void didStart(Uri? url) {
    if (url != null) _recordVisit(url);
    _loading = true;
    _error = null;
    notifyListeners();
  }

  Future<void> didStop(InAppWebViewController controller, Uri? url) async {
    if (url != null) _recordVisit(url);
    _loading = false;
    _error = null;
    await _refreshNavigation(controller);
    await refreshCookieMetadata();
    notifyListeners();
  }

  Future<void> didVisit(InAppWebViewController controller, Uri? url) async {
    if (url != null) _recordVisit(url);
    await _refreshNavigation(controller);
    notifyListeners();
  }

  void didProgress(int progress) {
    _loading = progress < 85;
    notifyListeners();
  }

  void didChangeTitle(String? value) {
    if (value == null || value.trim().isEmpty) return;
    _title = value.trim();
    notifyListeners();
  }

  void didFail(Object error) {
    _loading = false;
    _error = '$error';
    notifyListeners();
  }

  void minimize() {
    if (_minimized) return;
    _minimized = true;
    notifyListeners();
  }

  void restore() {
    if (!_minimized) return;
    _minimized = false;
    notifyListeners();
  }

  /// The bridge host calls this only after its injection/handshake succeeds.
  void markJsBridgeAttached() {
    _jsBridgeStatus = WebViewJsBridgeStatus.attached;
    notifyListeners();
  }

  /// Records a real bridged request; it is deliberately not updated by UI.
  void recordJsBridgeRequest() {
    _jsBridgeRequestCount++;
    notifyListeners();
  }

  void markJsBridgeFailed(Object error) {
    _jsBridgeStatus = WebViewJsBridgeStatus.failed;
    _error = '$error';
    notifyListeners();
  }

  Future<void> refreshCookieMetadata() async {
    try {
      final cookies = await CookieManager.instance().getCookies(
        url: WebUri.uri(_currentUrl),
      );
      _cookieCount = cookies.length;
    } catch (_) {
      // Some desktop/platform implementations do not expose cookie querying.
      // Keep the page usable and report only the last known metadata.
    }
  }

  Future<void> _refreshNavigation(InAppWebViewController controller) async {
    try {
      _canGoBack = await controller.canGoBack();
    } catch (_) {
      _canGoBack = false;
    }
    try {
      _canGoForward = await controller.canGoForward();
    } catch (_) {
      _canGoForward = false;
    }
  }


  void _recordVisit(Uri url) {
    _currentUrl = url;
    if (_history.isEmpty || _history.last != url) _history.add(url);
  }
}

enum WebViewJsBridgeStatus { unbound, attached, failed }

/// Sessions are explicitly released when a MiniApp task closes. This keeps
/// state stable across view updates without turning sessions into leaks.
class WebViewSessionRegistry extends ChangeNotifier {
  WebViewSessionRegistry._();
  static final WebViewSessionRegistry shared = WebViewSessionRegistry._();

  final Map<String, WebViewSession> _sessions = <String, WebViewSession>{};

  List<WebViewSession> get sessions =>
      List<WebViewSession>.unmodifiable(_sessions.values);

  WebViewSession obtain({required String id, required Uri url, String? title}) {
    final existing = _sessions[id];
    if (existing != null) return existing;
    final session = WebViewSession(id: id, initialUrl: url, title: title);
    _sessions[id] = session;
    notifyListeners();
    return session;
  }

  WebViewSession? find(String id) => _sessions[id];

  void release(String id) {
    final session = _sessions.remove(id);
    if (session == null) return;
    session.dispose();
    notifyListeners();
  }
}
