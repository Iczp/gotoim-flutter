import 'dart:io' show Platform, Process;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/windows/windows_window_adapter.dart';
import '../widgets/app_toast.dart';

/// 浏览器标签页模型
class BrowserTabItem {
  BrowserTabItem({
    required this.id,
    required this.url,
    required this.title,
    this.fallbackContent,
  });

  final String id;
  String url;
  String title;
  final String? fallbackContent;
  InAppWebViewController? controller;
  double progress = 0.0;
  bool isLoading = true;
  bool canGoBack = false;
  bool canGoForward = false;
  String? errorMessage;
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

  BrowserTabItem get _currentTab =>
      _tabs.isNotEmpty && _activeTabIndex < _tabs.length
          ? _tabs[_activeTabIndex]
          : _tabs.first;

  @override
  void initState() {
    super.initState();
    final firstTab = BrowserTabItem(
      id: 'tab_${DateTime.now().millisecondsSinceEpoch}',
      url: widget.initialUrl,
      title: widget.title ?? _extractHost(widget.initialUrl),
      fallbackContent: widget.fallbackContent,
    );
    _tabs.add(firstTab);

    if (widget.isSubWindow) {
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
      final args = call.arguments;
      if (args is Map && mounted) {
        final url = args['url'] as String?;
        if (url != null && url.isNotEmpty) {
          final title = args['title'] as String?;
          addTab(url: url, title: title, activate: true);
        }
      }
      return true;
    }
    return null;
  }

  @override
  void dispose() {
    _tabScrollController.dispose();
    super.dispose();
  }

  void addTab({
    required String url,
    String? title,
    bool activate = true,
  }) {
    // 检查是否已有相同 URL
    final existingIndex = _tabs.indexWhere((t) => t.url == url);
    if (existingIndex >= 0) {
      if (activate) {
        setState(() {
          _activeTabIndex = existingIndex;
        });
      }
      return;
    }

    final newTab = BrowserTabItem(
      id: 'tab_${DateTime.now().millisecondsSinceEpoch}_${_tabs.length}',
      url: url,
      title: title ?? _extractHost(url),
    );

    setState(() {
      _tabs.add(newTab);
      if (activate) {
        _activeTabIndex = _tabs.length - 1;
      }
    });

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
    if (_tabs.length <= 1) {
      _closeWindow();
      return;
    }

    setState(() {
      _tabs.removeAt(index);
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
      mainChannel.invokeMethod('request_undock_browser');
      WindowsWindowAdapter.close();
      return;
    }
    if (widget.onClose != null) {
      widget.onClose!();
    } else if (widget.isSubWindow) {
      WindowsWindowAdapter.close();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _refresh() async {
    final tab = _currentTab;
    setState(() {
      tab.isLoading = true;
      tab.errorMessage = null;
    });
    await tab.controller?.reload();
  }

  Future<void> _openInExternalBrowser() async {
    final url = _currentTab.url;
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

    final body = Column(
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
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF07C160)),
          ),

        // 3. 网页主内容视图 (使用 IndexedStack 保持各个 Tab 的状态和页面实例)
        Expanded(
          child: Container(
            color: isDark ? const Color(0xFF181818) : Colors.white,
            child: IndexedStack(
              index: _activeTabIndex,
              children: _tabs
                  .map((tab) => _buildTabWebView(context, tab, isDark))
                  .toList(),
            ),
          ),
        ),
      ],
    );

    if (widget.isSubWindow) {
      return Material(color: windowBg, child: SizedBox.expand(child: body));
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
    return Stack(
      fit: StackFit.expand,
      children: [
        if (InAppWebViewPlatform.instance != null)
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
              if (!mounted) return;
              setState(() {
                tab.progress = progress / 100.0;
                if (progress >= 100) {
                  tab.isLoading = false;
                }
              });
            },
            onTitleChanged: (controller, title) {
              if (!mounted || title == null || title.isEmpty) return;
              setState(() {
                tab.title = title;
              });
            },
            onLoadStart: (controller, url) {
              if (!mounted) return;
              setState(() {
                if (url != null) tab.url = url.toString();
                tab.errorMessage = null;
                tab.isLoading = true;
              });
            },
            onLoadStop: (controller, url) async {
              final canBack = await controller.canGoBack();
              final canForward = await controller.canGoForward();
              if (!mounted) return;
              setState(() {
                tab.errorMessage = null;
                tab.isLoading = false;
                tab.canGoBack = canBack;
                tab.canGoForward = canForward;
                if (url != null) tab.url = url.toString();
              });
            },
            onReceivedError: (controller, request, error) {
              if (!mounted ||
                  request.isForMainFrame == false ||
                  error.type == WebResourceErrorType.CANCELLED) {
                return;
              }
              setState(() {
                tab.isLoading = false;
                tab.errorMessage = error.description;
              });
            },
          )
        else
          _buildWebPreviewPlaceholder(context, tab, isDark),

        if (tab.errorMessage != null)
          _buildErrorFallback(context, tab, isDark),
      ],
    );
  }

  Widget _buildBrowserTopBar(
    BuildContext context,
    bool isDark,
    Color bg,
    Color border,
  ) {
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
            // 置顶图标 (仅独立窗口模式显示)
            if (!_isDocked)
              IconButton(
                icon: Icon(
                  _isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
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

            const SizedBox(width: 4),

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
                        separatorBuilder: (_, _) => const SizedBox(width: 4),
                        itemBuilder: (context, index) {
                          final tab = _tabs[index];
                          final isActive = index == _activeTabIndex;
                          final tabBg = isActive
                              ? (isDark ? const Color(0xFF1E1E1E) : Colors.white)
                              : Colors.transparent;

                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _activeTabIndex = index;
                              });
                            },
                            child: Container(
                              constraints: const BoxConstraints(
                                minWidth: 80,
                                maxWidth: 180,
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(
                                color: tabBg,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isActive ? border : Colors.transparent,
                                  width: 0.5,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.public_rounded,
                                    size: 14,
                                    color: isActive
                                        ? const Color(0xFF07C160)
                                        : Colors.grey,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      tab.title,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: isActive
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                        color: isActive
                                            ? (isDark ? Colors.white : Colors.black87)
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
                              ),
                            ),
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

            const SizedBox(width: 8),

            // 导航操作：后退、前进、刷新
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_rounded, size: 13),
              tooltip: '后退',
              visualDensity: VisualDensity.compact,
              onPressed: currentTab.canGoBack
                  ? () async {
                      await currentTab.controller?.goBack();
                    }
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward_ios_rounded, size: 13),
              tooltip: '前进',
              visualDensity: VisualDensity.compact,
              onPressed: currentTab.canGoForward
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

            // 在系统外部浏览器中打开
            IconButton(
              icon: const Icon(Icons.open_in_browser_rounded, size: 16),
              tooltip: '在系统默认浏览器中打开',
              visualDensity: VisualDensity.compact,
              onPressed: _openInExternalBrowser,
            ),

            // 复制网页链接
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
              // 嵌入状态下的控制按钮：弹出为独立窗口、关闭
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
              // 独立窗口状态下的控制按钮：嵌入到聊天窗口、最小化、最大化、关闭
              IconButton(
                icon: const Icon(Icons.vertical_align_bottom_rounded, size: 16),
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
        ),
      ),
    );
  }

  Widget _buildWebPreviewPlaceholder(
    BuildContext context,
    BrowserTabItem tab,
    bool isDark,
  ) {
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
    return Container(
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.wifi_off_rounded,
              size: 48,
              color: isDark ? Colors.grey[600] : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            const Text(
              '网页无法加载',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              tab.errorMessage ?? '请检查网络连接或稍后重试',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            if (tab.fallbackContent != null &&
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
                OutlinedButton(
                  onPressed: _refresh,
                  child: const Text('重新加载', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 12),
                FilledButton.tonal(
                  onPressed: _openInExternalBrowser,
                  child: const Text('在外部浏览器打开', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
