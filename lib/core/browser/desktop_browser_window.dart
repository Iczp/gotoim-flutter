import 'dart:async';
import 'dart:io' show Platform, Process;
import 'dart:ui' as ui;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/windows/windows_window_adapter.dart';
import '../security/url_security_service.dart';
import '../widgets/app_modal.dart';
import '../widgets/app_toast.dart';

/// 浏览器标签页模型
class BrowserTabItem {
  BrowserTabItem({
    required this.id,
    required this.url,
    required this.title,
    String? initialUrl,
    this.faviconUrl,
    this.thumbnail,
    this.fallbackContent,
    this.isInvalidUrl = false,
    this.isBlocked = false,
    this.isLoading = true,
    this.errorMessage,
    this.interceptReason,
  }) : initialUrl = initialUrl ?? url;

  final String id;
  final String initialUrl;
  String url;
  String title;
  String? faviconUrl;
  Uint8List? thumbnail;
  final String? fallbackContent;
  bool isInvalidUrl;
  bool isBlocked;
  InAppWebViewController? controller;
  double progress = 0.0;
  bool isLoading;
  bool canGoBack = false;
  bool canGoForward = false;
  String? errorMessage;
  String? interceptReason;

  void clearThumbnail() {
    thumbnail = null;
  }
}

/// 桌面端微信同款多标签页独立网页浏览器窗口 (DesktopBrowserWindow)
///
/// 核心特性：
/// 1. 多标签页（Multi-Tab）架构：打开不同网址时不覆盖，而是增加一个标签页；
/// 2. 内容区采用 `IndexedStack`：各个标签页保持独立独立的 WebView，切换不重新加载，输入表单与滚动位置不丢失；
/// 3. 支持 IPC 动态添加标签页（`browser_add_tab`）；
/// 4. 标签页支持：新建（`+`）、切换、关闭（`×`）、刷新、前进、后退；
/// 5. 网页控制：置顶（Pin）、复制链接、在系统默认浏览器中打开。
class DesktopBrowserWindow extends ConsumerStatefulWidget {
  const DesktopBrowserWindow({
    required this.initialUrl,
    this.title,
    this.fallbackContent,
    this.isSubWindow = false,
    this.onClose,
    this.onRegisterMethodHandler,
    super.key,
  });

  final String initialUrl;
  final String? title;
  final String? fallbackContent;
  final bool isSubWindow;
  final VoidCallback? onClose;
  final void Function(Future<dynamic> Function(MethodCall call) handler)?
      onRegisterMethodHandler;

  /// 标准化并校验 URL 格式（支持补全 https:// 协议、去除多余空白字符、拦截非法 scheme 与不合法域名）
  static String? validateAndNormalizeUrl(String? rawUrl) {
    if (rawUrl == null) return null;
    var url = rawUrl.trim();
    if (url.isEmpty) return null;

    if (url.startsWith('//')) {
      url = 'https:$url';
    } else if (!url.startsWith(RegExp(r'^[a-zA-Z][a-zA-Z0-9+\-.]*://'))) {
      final domainRegex = RegExp(
        r'^([a-zA-Z0-9\-]+\.)+[a-zA-Z]{2,}(:\d+)?(/.*|\?.*|#.*)?$',
      );
      final ipRegex = RegExp(
        r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(:\d+)?(/.*|\?.*|#.*)?$',
      );
      final localhostRegex = RegExp(
        r'^localhost(:\d+)?(/.*|\?.*|#.*)?$',
        caseSensitive: false,
      );
      if (domainRegex.hasMatch(url) ||
          ipRegex.hasMatch(url) ||
          localhostRegex.hasMatch(url)) {
        url = 'https://$url';
      } else {
        return null;
      }
    }

    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    final host = uri.host.trim();
    if (host.isEmpty) return null;

    final isLocalhost = host.toLowerCase() == 'localhost';
    final isIp =
        RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(host) ||
        host.contains(':');
    final isValidDomain = RegExp(
      r'^([a-zA-Z0-9\-]+\.)+[a-zA-Z]{2,}$',
    ).hasMatch(host);
    if (!isLocalhost && !isIp && !isValidDomain) return null;

    return uri.toString();
  }

  /// 唤起桌面端独立浏览器窗口
  static Future<void> open(
    BuildContext context, {
    required String url,
    String? title,
    String? fallbackContent,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder:
          (_) => DesktopBrowserWindow(
            initialUrl: url,
            title: title,
            fallbackContent: fallbackContent,
          ),
    );
  }

  @override
  ConsumerState<DesktopBrowserWindow> createState() =>
      _DesktopBrowserWindowState();
}

class _DesktopBrowserWindowState extends ConsumerState<DesktopBrowserWindow> {
  final List<BrowserTabItem> _tabs = [];
  int _activeTabIndex = 0;
  bool _isPinned = false;
  bool _isMaximized = false;
  bool _isDocked = false;
  final ScrollController _tabScrollController = ScrollController();
  bool _pendingNavigationReported = false;
  Timer? _navigationTimeoutTimer;
  BrowserTabItem? _hoveredTab;
  double _hoveredTabLeft = 8.0;
  Timer? _hoverPreviewTimer;

  void _reportLoadComplete(String url, String? title, {bool force = false}) {
    if (!force && _pendingNavigationReported) return;
    _pendingNavigationReported = true;
    _navigationTimeoutTimer?.cancel();
    _navigationTimeoutTimer = null;
    if (widget.isSubWindow) {
      try {
        const ipc = WindowMethodChannel(
          'gotoim/ipc_to_main',
          mode: ChannelMode.unidirectional,
        );
        ipc.invokeMethod('browser_load_completed', {
          'url': url,
          'title': title,
        });
      } catch (e) {
        debugPrint(
          '[Browser SubWindow] report browser_load_completed error: $e',
        );
      }
    }
  }

  void _startWaitingForTabLoad(String url, String? title) {
    _pendingNavigationReported = false;
    _navigationTimeoutTimer?.cancel();
    _navigationTimeoutTimer = Timer(const Duration(milliseconds: 3500), () {
      _reportLoadComplete(url, title);
    });
  }

  static final BrowserTabItem _emptyFallbackTab = BrowserTabItem(
    id: 'empty',
    url: '',
    title: '网页浏览',
    isLoading: false,
  );

  BrowserTabItem get _currentTab =>
      _tabs.isNotEmpty && _activeTabIndex < _tabs.length
          ? _tabs[_activeTabIndex]
          : (_tabs.isNotEmpty ? _tabs.first : _emptyFallbackTab);

  static String? _defaultFaviconUrl(String url) {
    try {
      final uri = Uri.tryParse(url);
      if (uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty) {
        return '${uri.scheme}://${uri.authority}/favicon.ico';
      }
    } catch (_) {}
    return null;
  }

  void _clearAllTabs() {
    _navigationTimeoutTimer?.cancel();
    _navigationTimeoutTimer = null;
    _hoverPreviewTimer?.cancel();
    _hoverPreviewTimer = null;
    _hoveredTab = null;
    _pendingNavigationReported = false;
    for (final t in _tabs) {
      t.clearThumbnail();
    }
    if (mounted) {
      setState(() {
        _tabs.clear();
        _activeTabIndex = 0;
      });
    } else {
      _tabs.clear();
      _activeTabIndex = 0;
    }
  }

  /// 截取当前激活标签页内容并压缩为 240px 宽的轻量级缩略图缓存至内存
  Future<void> _captureThumbnail(BrowserTabItem tab) async {
    final c = tab.controller;
    if (!mounted ||
        c == null ||
        tab.isBlocked ||
        tab.isInvalidUrl ||
        !_tabs.contains(tab) ||
        _currentTab != tab) {
      return;
    }
    try {
      final rawBytes = await c.takeScreenshot(
        screenshotConfiguration: ScreenshotConfiguration(
          compressFormat: CompressFormat.JPEG,
          quality: 60,
        ),
      );
      if (rawBytes == null || rawBytes.isEmpty || !mounted || !_tabs.contains(tab)) {
        return;
      }
      final codec = await ui.instantiateImageCodec(rawBytes, targetWidth: 240);
      final frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      frame.image.dispose();
      if (byteData == null || !mounted || !_tabs.contains(tab)) return;
      setState(() {
        tab.thumbnail = byteData.buffer.asUint8List();
      });
    } catch (_) {
      // 平台或当前页面状态不支持截图时静默回退至 Favicon 展示，不抛出异常
    }
  }

  /// 切换到目标标签页前，先为当前正在展示的激活标签页抓取最新状态缩略图
  Future<void> _switchToTab(int newIndex) async {
    if (newIndex < 0 || newIndex >= _tabs.length || newIndex == _activeTabIndex) {
      return;
    }
    final previousTab = _currentTab;
    if (_tabs.contains(previousTab) &&
        !previousTab.isBlocked &&
        !previousTab.isInvalidUrl &&
        previousTab.controller != null) {
      await _captureThumbnail(
        previousTab,
      ).timeout(const Duration(milliseconds: 120), onTimeout: () {});
    }
    if (!mounted || newIndex >= _tabs.length) return;
    setState(() {
      _activeTabIndex = newIndex;
    });
  }

  BrowserTabItem _createValidatedTab({
    required String rawUrl,
    String? title,
    String? fallbackContent,
  }) {
    final validUrl = DesktopBrowserWindow.validateAndNormalizeUrl(rawUrl);
    final tabId = 'tab_${DateTime.now().millisecondsSinceEpoch}_${_tabs.length}';
    if (validUrl != null) {
      return BrowserTabItem(
        id: tabId,
        url: validUrl,
        title: title ?? _extractHost(validUrl),
        faviconUrl: _defaultFaviconUrl(validUrl),
        fallbackContent: fallbackContent,
      );
    }
    final cleanedUrl = rawUrl.trim();
    return BrowserTabItem(
      id: tabId,
      url: cleanedUrl,
      title: title ?? '无效链接',
      fallbackContent: fallbackContent,
      isInvalidUrl: true,
      isLoading: false,
      errorMessage: '网址格式不正确，无法打开该页面：\n$cleanedUrl',
    );
  }

  Future<void> _verifyTabSecurity(BrowserTabItem tab, String targetUrl) async {
    try {
      final securityService = ref.read(urlSecurityServiceProvider);
      final res = await securityService.checkUrl(targetUrl);
      if (!mounted) return;
      if (res.isBlocked) {
        await tab.controller?.stopLoading();
        if (!mounted) return;
        setState(() {
          tab.isBlocked = true;
          tab.isLoading = false;
          tab.title = '已停止访问该网页';
          tab.errorMessage = res.message;
          tab.interceptReason = res.interceptReason;
        });
        _reportLoadComplete(tab.url, tab.title, force: true);
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    final firstTab = _createValidatedTab(
      rawUrl: widget.initialUrl,
      title: widget.title,
      fallbackContent: widget.fallbackContent,
    );
    _tabs.add(firstTab);

    if (!firstTab.isInvalidUrl) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _verifyTabSecurity(firstTab, firstTab.url);
      });
    }

    if (widget.isSubWindow) {
      if (firstTab.isInvalidUrl) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _reportLoadComplete(firstTab.url, firstTab.title, force: true);
        });
      } else {
        _startWaitingForTabLoad(firstTab.url, widget.title);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WindowsWindowAdapter.setupCustomTitleBar();
        WindowsWindowAdapter.isDocked().then((docked) {
          if (mounted && docked != _isDocked) {
            setState(() => _isDocked = docked);
          }
        });
        if (mounted) {
          setState(() {
            _isMaximized = WindowsWindowAdapter.isMaximized();
          });
        }
      });
    }

    if (widget.onRegisterMethodHandler != null) {
      widget.onRegisterMethodHandler!(_handleWindowMethodCall);
    } else if (widget.isSubWindow) {
      WindowController.fromCurrentEngine().then((controller) {
        controller.setWindowMethodHandler(_handleWindowMethodCall);
      }).catchError((_) {});
    }
  }

  @override
  void didUpdateWidget(covariant DesktopBrowserWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialUrl.isNotEmpty &&
        widget.initialUrl != oldWidget.initialUrl) {
      addTab(url: widget.initialUrl, title: widget.title, activate: true);
    }
  }

  Future<dynamic> _handleWindowMethodCall(MethodCall call) async {
    if (call.method == 'set_dock_mode') {
      final isDocked = call.arguments == true;
      if (mounted && _isDocked != isDocked) {
        setState(() => _isDocked = isDocked);
      }
      return true;
    }
    if (call.method == 'browser_clear_tabs') {
      _clearAllTabs();
      return true;
    }
    if (call.method == 'browser_add_tab') {
      final args = call.arguments;
      if (args is Map && mounted) {
        final url = args['url'] as String? ?? 'https://www.bing.com';
        final title = args['title'] as String?;
        addTab(url: url, title: title, activate: true);
      }
      return true;
    }
    if (call.method == 'update_payload') {
      _pendingNavigationReported = false;
      final args = call.arguments;
      if (args is Map && mounted) {
        final url = args['url'] as String?;
        if (url != null && url.isNotEmpty) {
          final title = args['title'] as String?;
          // 从关闭/隐藏状态重新唤醒打开浏览器时，确保清空旧 Tab，只保留新打开的页面
          _tabs.clear();
          _activeTabIndex = 0;
          addTab(url: url, title: title, activate: true);
        }
      }
      return true;
    }
    return null;
  }

  @override
  void dispose() {
    _navigationTimeoutTimer?.cancel();
    _hoverPreviewTimer?.cancel();
    for (final t in _tabs) {
      t.clearThumbnail();
    }
    _tabScrollController.dispose();
    super.dispose();
  }

  static String _canonicalUrlKey(String u) {
    var s = u.trim();
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  void addTab({
    required String url,
    String? title,
    bool activate = true,
  }) {
    final normalizedUrl = DesktopBrowserWindow.validateAndNormalizeUrl(url);
    final targetKeyUrl = normalizedUrl ?? url.trim();
    final canonicalTarget = _canonicalUrlKey(targetKeyUrl);

    // 检查是否已有相同 URL（同时比对当前 URL 与初始 URL，忽略末尾斜杠差异，防止重复新建 Tab 重新加载）
    final existingIndex = _tabs.indexWhere(
      (t) =>
          _canonicalUrlKey(t.url) == canonicalTarget ||
          _canonicalUrlKey(t.initialUrl) == canonicalTarget,
    );
    if (existingIndex >= 0) {
      if (activate && existingIndex != _activeTabIndex) {
        unawaited(_switchToTab(existingIndex));
      }
      _reportLoadComplete(
        targetKeyUrl,
        title ?? _tabs[existingIndex].title,
        force: true,
      );
      return;
    }

    if (activate && _tabs.isNotEmpty) {
      final prevTab = _currentTab;
      if (_tabs.contains(prevTab)) {
        unawaited(_captureThumbnail(prevTab));
      }
    }

    final newTab = _createValidatedTab(rawUrl: url, title: title);

    setState(() {
      _hoveredTab = null;
      _tabs.add(newTab);
      if (activate) {
        _activeTabIndex = _tabs.length - 1;
      }
    });

    if (newTab.isInvalidUrl) {
      _reportLoadComplete(newTab.url, newTab.title, force: true);
    } else {
      _startWaitingForTabLoad(newTab.url, newTab.title);
      _verifyTabSecurity(newTab, newTab.url);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_tabScrollController.hasClients) {
        _tabScrollController.animateTo(
          _tabScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _closeTab(int index) {
    _hoverPreviewTimer?.cancel();
    if (_tabs.length <= 1) {
      _closeWindow();
      return;
    }

    final removed = _tabs[index];
    removed.clearThumbnail();
    setState(() {
      if (_hoveredTab == removed) {
        _hoveredTab = null;
      }
      _tabs.removeAt(index);
      if (_activeTabIndex >= _tabs.length) {
        _activeTabIndex = _tabs.length - 1;
      }
    });
  }

  void _closeOtherTabs(int targetIndex) {
    if (_tabs.length <= 1) return;
    final keptTab = _tabs[targetIndex];
    for (var i = 0; i < _tabs.length; i++) {
      if (i != targetIndex) {
        _tabs[i].clearThumbnail();
      }
    }
    setState(() {
      _hoveredTab = null;
      _tabs.clear();
      _tabs.add(keptTab);
      _activeTabIndex = 0;
    });
  }

  void _closeRightTabs(int targetIndex) {
    if (targetIndex >= _tabs.length - 1) return;
    for (var i = targetIndex + 1; i < _tabs.length; i++) {
      _tabs[i].clearThumbnail();
    }
    setState(() {
      _hoveredTab = null;
      _tabs.removeRange(targetIndex + 1, _tabs.length);
      if (_activeTabIndex >= _tabs.length) {
        _activeTabIndex = _tabs.length - 1;
      }
    });
  }

  String _extractHost(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.host.isNotEmpty) return uri.host;
    } catch (_) {}
    return '网页浏览';
  }

  void _closeWindow() {
    if (_isDocked) {
      const mainChannel = WindowMethodChannel(
        'gotoim/ipc_to_main',
        mode: ChannelMode.unidirectional,
      );
      mainChannel.invokeMethod('request_close_docked_browser');
      return;
    }
    if (widget.onClose != null) {
      widget.onClose!();
    } else if (widget.isSubWindow) {
      WindowsWindowAdapter.close();
      _clearAllTabs();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _refresh() async {
    final tab = _currentTab;
    if (tab.isInvalidUrl) {
      showToast('网址格式无效，无法重新加载', type: ToastType.error);
      return;
    }
    if (tab.isBlocked) {
      showToast('该网页已被安全策略拦截，无法重新加载', type: ToastType.error);
      return;
    }
    setState(() {
      tab.isLoading = true;
      tab.errorMessage = null;
    });
    await tab.controller?.reload();
  }

  Future<void> _openExternalUrl(String url) async {
    try {
      await Clipboard.setData(ClipboardData(text: url));
      final uri = Uri.tryParse(url);
      if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
        showToast('已复制网页链接至剪贴板: $url', type: ToastType.success);
        return;
      }

      showToast('正在调起系统浏览器...', type: ToastType.info);
      if (!kIsWeb) {
        if (Platform.isWindows) {
          await Process.run('explorer.exe', [url], runInShell: false);
        } else if (Platform.isMacOS) {
          await Process.run('open', [url], runInShell: false);
        } else if (Platform.isLinux) {
          await Process.run('xdg-open', [url], runInShell: false);
        }
      }
    } catch (_) {
      showToast('已复制网页链接至剪贴板: $url', type: ToastType.success);
    }
  }

  Future<void> _openInExternalBrowser() => _openExternalUrl(_currentTab.url);

  void _showTabContextMenu(
    BuildContext context,
    Offset position,
    int index,
  ) async {
    final tab = _tabs[index];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isDark ? const Color(0x2AFFFFFF) : const Color(0x1F000000),
          width: 0.5,
        ),
      ),
      items: [
        const PopupMenuItem(
          value: 'reload',
          height: 34,
          child: Row(
            children: [
              Icon(Icons.refresh_rounded, size: 15),
              SizedBox(width: 8),
              Text('重新加载', style: TextStyle(fontSize: 12.5)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'copy_url',
          height: 34,
          child: Row(
            children: [
              Icon(Icons.link_rounded, size: 15),
              SizedBox(width: 8),
              Text('复制链接', style: TextStyle(fontSize: 12.5)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'open_external',
          height: 34,
          child: Row(
            children: [
              Icon(Icons.open_in_browser_rounded, size: 15),
              SizedBox(width: 8),
              Text('在系统浏览器打开', style: TextStyle(fontSize: 12.5)),
            ],
          ),
        ),
        const PopupMenuDivider(height: 6),
        PopupMenuItem(
          value: 'close',
          height: 34,
          child: const Row(
            children: [
              Icon(Icons.close_rounded, size: 15),
              SizedBox(width: 8),
              Text('关闭标签页', style: TextStyle(fontSize: 12.5)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'close_others',
          enabled: _tabs.length > 1,
          height: 34,
          child: const Row(
            children: [
              Icon(Icons.tab_unselected_rounded, size: 15),
              SizedBox(width: 8),
              Text('关闭其他标签页', style: TextStyle(fontSize: 12.5)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'close_right',
          enabled: index < _tabs.length - 1,
          height: 34,
          child: const Row(
            children: [
              Icon(Icons.arrow_forward_rounded, size: 15),
              SizedBox(width: 8),
              Text('关闭右侧标签页', style: TextStyle(fontSize: 12.5)),
            ],
          ),
        ),
        const PopupMenuDivider(height: 6),
        const PopupMenuItem(
          value: 'new_tab',
          height: 34,
          child: Row(
            children: [
              Icon(Icons.add_rounded, size: 15),
              SizedBox(width: 8),
              Text('新建标签页', style: TextStyle(fontSize: 12.5)),
            ],
          ),
        ),
      ],
    );

    if (selected == null) return;
    switch (selected) {
      case 'reload':
        setState(() {
          tab.isLoading = true;
          tab.errorMessage = null;
        });
        await tab.controller?.reload();
        break;
      case 'copy_url':
        Clipboard.setData(ClipboardData(text: tab.url));
        showToast('网页链接已复制到剪贴板', type: ToastType.success);
        break;
      case 'open_external':
        _openExternalUrl(tab.url);
        break;
      case 'close':
        _closeTab(index);
        break;
      case 'close_others':
        _closeOtherTabs(index);
        break;
      case 'close_right':
        _closeRightTabs(index);
        break;
      case 'new_tab':
        addTab(
          url: 'https://www.bing.com',
          title: '新标签页',
          activate: true,
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final windowBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final topBarBg = isDark ? const Color(0xFF232323) : const Color(0xFFF3F3F3);
    final borderColor =
        isDark ? const Color(0x1FFFFFFF) : const Color(0x1F000000);

    final screenSize = MediaQuery.of(context).size;
    final dialogWidth =
        _isMaximized
            ? screenSize.width
            : (screenSize.width - 40).clamp(0.0, 1080.0);
    final dialogHeight =
        _isMaximized
            ? screenSize.height
            : (screenSize.height - 40).clamp(0.0, 760.0);

    final currentTab = _currentTab;
    final windowLogicalWidth =
        widget.isSubWindow ? screenSize.width : dialogWidth;

    final body = Stack(
      fit: StackFit.expand,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. 顶部浏览器工具栏 (含置顶、多标签栏、导航与控制按钮)
            _buildBrowserTopBar(context, isDark, topBarBg, borderColor),

            // 2. 加载进度条
            if (currentTab.isLoading && currentTab.progress < 1.0)
              LinearProgressIndicator(
                value: currentTab.progress,
                minHeight: 2,
                backgroundColor: Colors.transparent,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF07C160),
                ),
              ),

            // 3. 网页主内容视图 (使用 IndexedStack 保持各个 Tab 的状态和页面实例)
            Expanded(
              child: Container(
                color: isDark ? const Color(0xFF181818) : Colors.white,
                child:
                    _tabs.isEmpty
                        ? const SizedBox.shrink()
                        : IndexedStack(
                          index: _activeTabIndex.clamp(0, _tabs.length - 1),
                          children:
                              _tabs
                                  .map(
                                    (tab) =>
                                        _buildTabWebView(context, tab, isDark),
                                  )
                                  .toList(),
                        ),
              ),
            ),
          ],
        ),
        if (_hoveredTab != null && _tabs.contains(_hoveredTab))
          Positioned(
            top: 46,
            left: _hoveredTabLeft.clamp(
              8.0,
              (windowLogicalWidth - 252.0).clamp(8.0, double.infinity),
            ),
            child: IgnorePointer(
              child: _buildTabHoverPreviewCard(
                context,
                _hoveredTab!,
                isDark,
                borderColor,
              ),
            ),
          ),
      ],
    );

    if (widget.isSubWindow) {
      Widget content = Material(color: windowBg, child: SizedBox.expand(child: body));
      if (!_isDocked) {
        content = Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) {
            WindowsWindowAdapter.bringToFront();
          },
          child: content,
        );
      }
      return content;
    }

    return Center(
      child: Material(
        color: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: dialogWidth,
          height: dialogHeight,
          decoration: BoxDecoration(
            color: windowBg,
            borderRadius:
                _isMaximized ? BorderRadius.zero : BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 36,
                spreadRadius: 4,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: body,
        ),
      ),
    );
  }

  Widget _buildTabWebView(
    BuildContext context,
    BrowserTabItem tab,
    bool isDark,
  ) {
    final securityService = ref.watch(urlSecurityServiceProvider);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (!tab.isInvalidUrl &&
            !tab.isBlocked &&
            InAppWebViewPlatform.instance != null)
          InAppWebView(
            key: ValueKey('webview_${tab.id}'),
            initialUrlRequest: URLRequest(url: WebUri(tab.url)),
            initialSettings: InAppWebViewSettings(
              useShouldOverrideUrlLoading: false,
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              javaScriptEnabled: true,
              isInspectable: true,
            ),
            onWebViewCreated: (controller) {
              tab.controller = controller;
            },
            onProgressChanged: (controller, progress) {
              if (!mounted || tab.isBlocked) return;
              setState(() {
                tab.progress = progress / 100.0;
                if (progress >= 100) {
                  tab.isLoading = false;
                }
              });
              if (progress >= 100) {
                _reportLoadComplete(tab.url, tab.title);
              }
            },
            onTitleChanged: (controller, title) {
              if (!mounted || tab.isBlocked || title == null || title.isEmpty) {
                return;
              }
              setState(() {
                tab.title = title;
              });
            },
            onLoadStart: (controller, url) async {
              if (!mounted) return;
              final currentUrl = url?.toString();
              setState(() {
                if (currentUrl != null) {
                  tab.url = currentUrl;
                  tab.faviconUrl ??= _defaultFaviconUrl(currentUrl);
                }
                tab.errorMessage = null;
                tab.isLoading = true;
              });
              if (currentUrl != null &&
                  currentUrl.startsWith(RegExp(r'^https?://'))) {
                await _verifyTabSecurity(tab, currentUrl);
              }
            },
            onLoadStop: (controller, url) async {
              if (tab.isBlocked) return;
              final canBack = await controller.canGoBack();
              final canForward = await controller.canGoForward();
              if (!mounted || tab.isBlocked) return;
              setState(() {
                tab.errorMessage = null;
                tab.isLoading = false;
                tab.canGoBack = canBack;
                tab.canGoForward = canForward;
                if (url != null) {
                  tab.url = url.toString();
                  tab.faviconUrl ??= _defaultFaviconUrl(tab.url);
                }
              });
              _reportLoadComplete(tab.url, tab.title);
              Future<void>.delayed(const Duration(milliseconds: 500), () {
                if (mounted && !tab.isBlocked && _tabs.contains(tab)) {
                  _captureThumbnail(tab);
                }
              });
              try {
                final fav = await controller.evaluateJavascript(
                  source: '''
                    (function() {
                      var links = document.querySelectorAll('link[rel*="icon"]');
                      for (var i = 0; i < links.length; i++) {
                        if (links[i].href) return links[i].href;
                      }
                      return location.origin + '/favicon.ico';
                    })();
                  ''',
                );
                if (mounted &&
                    !tab.isBlocked &&
                    fav is String &&
                    fav.startsWith(RegExp(r'^https?://')) &&
                    fav != tab.faviconUrl) {
                  setState(() {
                    tab.faviconUrl = fav;
                  });
                }
              } catch (_) {}
            },
            onDownloadStarting: (controller, downloadStartRequest) async {
              final downloadUrl = downloadStartRequest.url.toString();
              if (securityService.isDangerousDownload(downloadUrl)) {
                if (!mounted) return DownloadStartResponse(handled: true);
                final confirmed = await showConfirmModal(
                  context: context,
                  title: '风险文件下载警告',
                  message:
                      '该网页试图下载可执行程序或安装包：\n$downloadUrl\n\n此类文件可能包含木马或恶意代码，建议您在外部浏览器核实来源后谨慎处理。',
                  confirmText: '前往外部浏览器处理',
                  cancelText: '取消下载',
                );
                if (confirmed && mounted) {
                  await _openExternalUrl(downloadUrl);
                }
              } else {
                await _openExternalUrl(downloadUrl);
              }
              return DownloadStartResponse(handled: true);
            },
            onReceivedError: (controller, request, error) {
              if (!mounted ||
                  tab.isBlocked ||
                  request.isForMainFrame == false ||
                  error.type == WebResourceErrorType.CANCELLED) {
                return;
              }
              setState(() {
                tab.isLoading = false;
                tab.errorMessage = error.description;
              });
              _reportLoadComplete(tab.url, tab.title);
            },
          )
        else if (!tab.isInvalidUrl && !tab.isBlocked)
          _buildWebPreviewPlaceholder(context, tab, isDark),

        if (tab.errorMessage != null || tab.isBlocked || tab.isInvalidUrl)
          _buildErrorFallback(context, tab, isDark),
      ],
    );
  }

  Widget _buildTabFavicon(
    BrowserTabItem tab, {
    required bool isActive,
    required double size,
  }) {
    if (tab.isBlocked) {
      return Icon(Icons.gpp_bad_rounded, size: size, color: Colors.redAccent);
    }
    if (tab.isInvalidUrl) {
      return Icon(
        Icons.link_off_rounded,
        size: size,
        color: Colors.orangeAccent,
      );
    }
    final favUrl = tab.faviconUrl ?? _defaultFaviconUrl(tab.url);
    final fallbackIcon = Icon(
      Icons.public_rounded,
      size: size,
      color: isActive ? const Color(0xFF07C160) : Colors.grey,
    );
    if (favUrl != null && favUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: Image.network(
          favUrl,
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => fallbackIcon,
        ),
      );
    }
    return fallbackIcon;
  }

  Widget _buildTabHoverPreviewCard(
    BuildContext context,
    BrowserTabItem tab,
    bool isDark,
    Color borderColor,
  ) {
    final cardBg = isDark ? const Color(0xFF282828) : Colors.white;
    final subTextColor = isDark ? Colors.white54 : Colors.black54;
    final thumbBytes = tab.thumbnail;

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.18),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (thumbBytes != null && thumbBytes.isNotEmpty)
            Container(
              height: 136,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
                border: Border(
                  bottom: BorderSide(color: borderColor, width: 0.5),
                ),
              ),
              child: Image.memory(
                thumbBytes,
                width: 240,
                height: 136,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                gaplessPlayback: true,
              ),
            )
          else
            Container(
              height: 76,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF7F8FA),
                border: Border(
                  bottom: BorderSide(color: borderColor, width: 0.5),
                ),
              ),
              child:
                  tab.isLoading
                      ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFF07C160),
                          ),
                        ),
                      )
                      : _buildTabFavicon(tab, isActive: true, size: 28),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    _buildTabFavicon(tab, isActive: true, size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        tab.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  _extractHost(tab.url),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: subTextColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrowserTopBar(
    BuildContext context,
    bool isDark,
    Color bg,
    Color border,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = _isDocked || constraints.maxWidth < 620.0;
        final currentTab = _currentTab;

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanStart: (_) {
            if (widget.isSubWindow && !_isDocked) {
              WindowsWindowAdapter.startDragging();
            }
          },
          onDoubleTap: () {
            if (widget.isSubWindow && !_isDocked) {
              WindowsWindowAdapter.toggleMaximize();
              if (mounted) {
                setState(() {
                  _isMaximized = WindowsWindowAdapter.isMaximized();
                });
              }
            }
          },
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: bg,
              border: Border(bottom: BorderSide(color: border, width: 0.5)),
            ),
            child: Row(
              children: [
                // 置顶图标 (仅独立大窗口模式显示，节省空间)
                if (!_isDocked && !isCompact)
                  IconButton(
                    icon: Icon(
                      _isPinned
                          ? Icons.push_pin_rounded
                          : Icons.push_pin_outlined,
                      size: 16,
                      color: _isPinned ? const Color(0xFF07C160) : Colors.grey,
                    ),
                    tooltip: _isPinned ? '取消置顶' : '固定置顶',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      setState(() {
                        _isPinned = !_isPinned;
                      });
                      if (widget.isSubWindow) {
                        WindowsWindowAdapter.setAlwaysOnTop(_isPinned);
                      }
                    },
                  ),

                if (!_isDocked && !isCompact) const SizedBox(width: 4),

                // 多标签页水平列表
                Expanded(
                  child: SizedBox(
                    height: 34,
                    child: Row(
                      children: [
                        Expanded(
                          child: ListView.separated(
                            controller: _tabScrollController,
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            itemCount: _tabs.length,
                            separatorBuilder:
                                (_, _) => const SizedBox(width: 4),
                            itemBuilder: (context, index) {
                              final tab = _tabs[index];
                              final isActive = index == _activeTabIndex;
                              // 空间小时：只有当前活跃 Tab 显示完整标题与关闭按钮，其他 Tab 仅显示图标
                              final showFullTab = isActive || !isCompact;
                              final tabBg =
                                  isActive
                                      ? (isDark
                                          ? const Color(0xFF1E1E1E)
                                          : Colors.white)
                                      : Colors.transparent;

                              Widget tabContent;
                              if (showFullTab) {
                                tabContent = Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildTabFavicon(
                                      tab,
                                      isActive: isActive,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        tab.title,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight:
                                              isActive
                                                  ? FontWeight.w600
                                                  : FontWeight.normal,
                                          color:
                                              isActive
                                                  ? (isDark
                                                      ? Colors.white
                                                      : Colors.black87)
                                                  : Colors.grey,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    InkWell(
                                      borderRadius: BorderRadius.circular(4),
                                      onTap: () => _closeTab(index),
                                      child: const Padding(
                                        padding: EdgeInsets.all(2),
                                        child: Icon(
                                          Icons.close_rounded,
                                          size: 13,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              } else {
                                tabContent = Center(
                                  child: _buildTabFavicon(
                                    tab,
                                    isActive: isActive,
                                    size: 15,
                                  ),
                                );
                              }

                              final Widget tabWidget = Container(
                                constraints: BoxConstraints(
                                  minWidth: showFullTab ? 72 : 32,
                                  maxWidth:
                                      showFullTab
                                          ? (isCompact ? 140 : 180)
                                          : 32,
                                ),
                                padding: EdgeInsets.symmetric(
                                  horizontal: showFullTab ? 8 : 4,
                                ),
                                decoration: BoxDecoration(
                                  color: tabBg,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color:
                                        isActive ? border : Colors.transparent,
                                    width: 0.5,
                                  ),
                                ),
                                child: tabContent,
                              );

                              return Builder(
                                builder: (tabItemContext) {
                                  return MouseRegion(
                                    onEnter: (_) {
                                      _hoverPreviewTimer?.cancel();
                                      double leftOffset = 8.0;
                                      final tabBox =
                                          tabItemContext.findRenderObject()
                                              as RenderBox?;
                                      final winBox =
                                          context.findRenderObject()
                                              as RenderBox?;
                                      if (tabBox != null &&
                                          winBox != null &&
                                          tabBox.hasSize &&
                                          winBox.hasSize) {
                                        final pos = tabBox.localToGlobal(
                                          Offset.zero,
                                          ancestor: winBox,
                                        );
                                        leftOffset = pos.dx;
                                      }
                                      _hoverPreviewTimer = Timer(
                                        const Duration(milliseconds: 350),
                                        () async {
                                          if (!mounted || !_tabs.contains(tab)) {
                                            return;
                                          }
                                          if (tab == _currentTab &&
                                              tab.thumbnail == null &&
                                              !tab.isLoading) {
                                            await _captureThumbnail(tab);
                                          }
                                          if (!mounted || !_tabs.contains(tab)) {
                                            return;
                                          }
                                          setState(() {
                                            _hoveredTab = tab;
                                            _hoveredTabLeft = leftOffset;
                                          });
                                        },
                                      );
                                    },
                                    onExit: (_) {
                                      _hoverPreviewTimer?.cancel();
                                      if (_hoveredTab == tab && mounted) {
                                        setState(() {
                                          _hoveredTab = null;
                                        });
                                      }
                                    },
                                    child: GestureDetector(
                                      onTap: () {
                                        _hoverPreviewTimer?.cancel();
                                        if (_hoveredTab != null) {
                                          setState(() => _hoveredTab = null);
                                        }
                                        _switchToTab(index);
                                      },
                                      onSecondaryTapUp: (details) {
                                        _hoverPreviewTimer?.cancel();
                                        if (_hoveredTab != null) {
                                          setState(() => _hoveredTab = null);
                                        }
                                        _showTabContextMenu(
                                          context,
                                          details.globalPosition,
                                          index,
                                        );
                                      },
                                      child: tabWidget,
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 4),
                        // 新建标签页按钮 (+)
                        IconButton(
                          icon: const Icon(Icons.add_rounded, size: 18),
                          tooltip: '新建标签页',
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            addTab(
                              url: 'https://www.bing.com',
                              title: '新标签页',
                              activate: true,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 6),

                // ── 右侧操作区：在空间小的时候，仅显示三个点和关闭 ──────────────
                if (isCompact) ...[
                  _buildMoreActionsMenu(context, isDark, currentTab),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 17),
                    tooltip: '关闭',
                    visualDensity: VisualDensity.compact,
                    onPressed: _closeWindow,
                  ),
                ] else ...[
                  // 宽屏模式：展开所有常用工具与控制按钮
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_rounded, size: 13),
                    tooltip: '后退',
                    visualDensity: VisualDensity.compact,
                    onPressed:
                        currentTab.canGoBack
                            ? () async {
                              await currentTab.controller?.goBack();
                            }
                            : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios_rounded, size: 13),
                    tooltip: '前进',
                    visualDensity: VisualDensity.compact,
                    onPressed:
                        currentTab.canGoForward
                            ? () async {
                              await currentTab.controller?.goForward();
                            }
                            : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    tooltip: '重新加载',
                    visualDensity: VisualDensity.compact,
                    onPressed: _refresh,
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                    tooltip: '在系统默认浏览器中打开',
                    visualDensity: VisualDensity.compact,
                    onPressed: _openInExternalBrowser,
                  ),
                  IconButton(
                    icon: const Icon(Icons.link_rounded, size: 16),
                    tooltip: '复制链接',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: currentTab.url));
                      showToast('网页链接已复制到剪贴板', type: ToastType.success);
                    },
                  ),
                  const SizedBox(width: 6),
                  if (_isDocked) ...[
                    IconButton(
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      tooltip: '弹出为独立窗口',
                      visualDensity: VisualDensity.compact,
                      onPressed: () async {
                        const mainChannel = WindowMethodChannel(
                          'gotoim/ipc_to_main',
                          mode: ChannelMode.unidirectional,
                        );
                        await mainChannel.invokeMethod('request_undock_browser');
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 17),
                      tooltip: '关闭',
                      visualDensity: VisualDensity.compact,
                      onPressed: _closeWindow,
                    ),
                  ] else ...[
                    IconButton(
                      icon: const Icon(
                        Icons.vertical_align_bottom_rounded,
                        size: 16,
                      ),
                      tooltip: '嵌入到聊天窗口',
                      visualDensity: VisualDensity.compact,
                      onPressed: () async {
                        const mainChannel = WindowMethodChannel(
                          'gotoim/ipc_to_main',
                          mode: ChannelMode.unidirectional,
                        );
                        await mainChannel.invokeMethod('request_dock_browser', {
                          'url': currentTab.url,
                          'title': currentTab.title,
                        });
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_rounded, size: 16),
                      tooltip: '最小化',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        if (widget.isSubWindow) {
                          WindowsWindowAdapter.minimize();
                        } else {
                          Navigator.of(context).maybePop();
                        }
                      },
                    ),
                    IconButton(
                      icon: Icon(
                        _isMaximized
                            ? Icons.filter_none_rounded
                            : Icons.crop_square_rounded,
                        size: 15,
                      ),
                      tooltip: _isMaximized ? '还原窗口' : '最大化窗口',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        if (widget.isSubWindow) {
                          WindowsWindowAdapter.toggleMaximize();
                          if (mounted) {
                            setState(() {
                              _isMaximized = WindowsWindowAdapter.isMaximized();
                            });
                          }
                        } else {
                          setState(() {
                            _isMaximized = !_isMaximized;
                          });
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 17),
                      tooltip: '关闭窗口',
                      visualDensity: VisualDensity.compact,
                      onPressed: _closeWindow,
                    ),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// 空间小时的“三个点”下拉更多菜单
  Widget _buildMoreActionsMenu(
    BuildContext context,
    bool isDark,
    BrowserTabItem currentTab,
  ) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_horiz_rounded, size: 18),
      tooltip: '更多选项',
      offset: const Offset(0, 36),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isDark ? const Color(0x2AFFFFFF) : const Color(0x1F000000),
          width: 0.5,
        ),
      ),
      onSelected: (value) async {
        switch (value) {
          case 'back':
            if (currentTab.canGoBack) {
              await currentTab.controller?.goBack();
            }
            break;
          case 'forward':
            if (currentTab.canGoForward) {
              await currentTab.controller?.goForward();
            }
            break;
          case 'refresh':
            _refresh();
            break;
          case 'copy_url':
            Clipboard.setData(ClipboardData(text: currentTab.url));
            showToast('网页链接已复制到剪贴板', type: ToastType.success);
            break;
          case 'open_external':
            _openInExternalBrowser();
            break;
          case 'undock':
            const mainChannel = WindowMethodChannel(
              'gotoim/ipc_to_main',
              mode: ChannelMode.unidirectional,
            );
            await mainChannel.invokeMethod('request_undock_browser');
            break;
          case 'dock':
            const mainChannel = WindowMethodChannel(
              'gotoim/ipc_to_main',
              mode: ChannelMode.unidirectional,
            );
            await mainChannel.invokeMethod('request_dock_browser', {
              'url': currentTab.url,
              'title': currentTab.title,
            });
            break;
          case 'pin':
            setState(() {
              _isPinned = !_isPinned;
            });
            if (widget.isSubWindow) {
              WindowsWindowAdapter.setAlwaysOnTop(_isPinned);
            }
            break;
          case 'minimize':
            if (widget.isSubWindow) {
              WindowsWindowAdapter.minimize();
            } else {
              Navigator.of(context).maybePop();
            }
            break;
          case 'maximize':
            if (widget.isSubWindow) {
              WindowsWindowAdapter.toggleMaximize();
              if (mounted) {
                setState(() {
                  _isMaximized = WindowsWindowAdapter.isMaximized();
                });
              }
            }
            break;
          case 'new_tab':
            addTab(
              url: 'https://www.bing.com',
              title: '新标签页',
              activate: true,
            );
            break;
        }
      },
      itemBuilder:
          (context) => [
            PopupMenuItem(
              value: 'back',
              enabled: currentTab.canGoBack,
              height: 36,
              child: const Row(
                children: [
                  Icon(Icons.arrow_back_ios_rounded, size: 13),
                  SizedBox(width: 10),
                  Text('后退', style: TextStyle(fontSize: 13)),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'forward',
              enabled: currentTab.canGoForward,
              height: 36,
              child: const Row(
                children: [
                  Icon(Icons.arrow_forward_ios_rounded, size: 13),
                  SizedBox(width: 10),
                  Text('前进', style: TextStyle(fontSize: 13)),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'refresh',
              height: 36,
              child: Row(
                children: [
                  Icon(Icons.refresh_rounded, size: 16),
                  SizedBox(width: 10),
                  Text('重新加载', style: TextStyle(fontSize: 13)),
                ],
              ),
            ),
            const PopupMenuDivider(height: 8),
            const PopupMenuItem(
              value: 'copy_url',
              height: 36,
              child: Row(
                children: [
                  Icon(Icons.link_rounded, size: 16),
                  SizedBox(width: 10),
                  Text('复制链接', style: TextStyle(fontSize: 13)),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'open_external',
              height: 36,
              child: Row(
                children: [
                  Icon(Icons.open_in_browser_rounded, size: 16),
                  SizedBox(width: 10),
                  Text('在系统默认浏览器打开', style: TextStyle(fontSize: 13)),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'new_tab',
              height: 36,
              child: Row(
                children: [
                  Icon(Icons.add_rounded, size: 16),
                  SizedBox(width: 10),
                  Text('新建标签页', style: TextStyle(fontSize: 13)),
                ],
              ),
            ),
            const PopupMenuDivider(height: 8),
            if (_isDocked)
              const PopupMenuItem(
                value: 'undock',
                height: 36,
                child: Row(
                  children: [
                    Icon(Icons.open_in_new_rounded, size: 16),
                    SizedBox(width: 10),
                    Text('弹出为独立窗口', style: TextStyle(fontSize: 13)),
                  ],
                ),
              )
            else ...[
              const PopupMenuItem(
                value: 'dock',
                height: 36,
                child: Row(
                  children: [
                    Icon(Icons.vertical_align_bottom_rounded, size: 16),
                    SizedBox(width: 10),
                    Text('嵌入到聊天窗口', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'pin',
                height: 36,
                child: Row(
                  children: [
                    Icon(
                      _isPinned
                          ? Icons.push_pin_rounded
                          : Icons.push_pin_outlined,
                      size: 16,
                      color: _isPinned ? const Color(0xFF07C160) : null,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _isPinned ? '取消置顶' : '固定置顶',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'minimize',
                height: 36,
                child: Row(
                  children: [
                    Icon(Icons.remove_rounded, size: 16),
                    SizedBox(width: 10),
                    Text('最小化', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'maximize',
                height: 36,
                child: Row(
                  children: [
                    Icon(
                      _isMaximized
                          ? Icons.filter_none_rounded
                          : Icons.crop_square_rounded,
                      size: 15,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _isMaximized ? '还原窗口' : '最大化',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ],
    );
  }

  Widget _buildWebPreviewPlaceholder(
    BuildContext context,
    BrowserTabItem tab,
    bool isDark,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportLoadComplete(tab.url, tab.title);
    });
    return Container(
      color: isDark ? const Color(0xFF181818) : const Color(0xFFFAFAFA),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFF07C160).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.language_rounded,
              size: 36,
              color: Color(0xFF07C160),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            tab.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            tab.url,
            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF282828) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? const Color(0x1FFFFFFF) : const Color(0x1F000000),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: 16,
                  color: Color(0xFF07C160),
                ),
                SizedBox(width: 6),
                Text('WebView 容器就绪 · 独立进程沙箱', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorFallback(
    BuildContext context,
    BrowserTabItem tab,
    bool isDark,
  ) {
    final isBlocked = tab.isBlocked;
    final isInvalid = tab.isInvalidUrl;
    return Container(
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      padding: const EdgeInsets.all(32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isBlocked)
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.gpp_bad_rounded,
                    size: 38,
                    color: Colors.red,
                  ),
                )
              else
                Icon(
                  isInvalid ? Icons.link_off_rounded : Icons.wifi_off_rounded,
                  size: 48,
                  color: isDark ? Colors.grey[600] : Colors.grey[400],
                ),
              const SizedBox(height: 16),
              Text(
                isBlocked
                    ? '已停止访问该网页'
                    : (isInvalid ? '网址格式无效' : '网页无法加载'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tab.errorMessage ??
                    (isBlocked
                        ? '该网页可能包含违法违规、欺诈钓鱼或恶意软件风险，为保护您的账号与财产安全，系统已阻止访问。'
                        : (isInvalid
                            ? '该链接不是合法的 http/https 网址'
                            : '请检查网络连接或稍后重试')),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              if (isBlocked || isInvalid) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        tab.url,
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                      if (isBlocked &&
                          tab.interceptReason != null &&
                          tab.interceptReason!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          '拦截原因：${tab.interceptReason}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Colors.redAccent,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (!isBlocked &&
                  tab.fallbackContent != null &&
                  tab.fallbackContent!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  constraints: const BoxConstraints(maxHeight: 180),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                        isDark
                            ? const Color(0xFF282828)
                            : const Color(0xFFF7F7F7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      tab.fallbackContent!,
                      style: const TextStyle(fontSize: 12, height: 1.5),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isBlocked || isInvalid) ...[
                    OutlinedButton(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: tab.url));
                        showToast('链接已复制到剪贴板', type: ToastType.success);
                      },
                      child: const Text('复制链接', style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.tonal(
                      onPressed: () => _closeTab(_activeTabIndex),
                      child: const Text(
                        '关闭标签页',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ] else ...[
                    OutlinedButton(
                      onPressed: _refresh,
                      child: const Text('重新加载', style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.tonal(
                      onPressed: _openInExternalBrowser,
                      child: const Text(
                        '在外部浏览器打开',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
