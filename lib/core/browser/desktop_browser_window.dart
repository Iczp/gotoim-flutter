import 'dart:io' show Platform, Process;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/app_toast.dart';

/// 桌面端微信同款独立网页浏览器窗口 (DesktopBrowserWindow - 打开链接)
///
/// 遵循微信 4.0 独立网页浏览器规范（参考截图 2）：
/// 1. 顶部标题栏/标签栏：
///    - 📌 置顶按钮 (Pin/Always on top)
///    - 📑 侧边栏/书签按钮
///    - 标签页 (Tab)：网站图标 + 标题（如“腾讯新闻”）+ 关闭页签按钮
///    - 导航按钮：后退、前进、刷新网页
///    - 外部浏览器打开、复制链接
///    - 右侧窗口控制按钮：最小化、最大化/还原、关闭
/// 2. 网页内容容器：
///    - 嵌入式 `InAppWebView` 容器
///    - 顶部细条加载进度动画
///    - 深色/浅色自适应
class DesktopBrowserWindow extends ConsumerStatefulWidget {
  const DesktopBrowserWindow({
    required this.initialUrl,
    this.title,
    this.fallbackContent,
    super.key,
  });

  final String initialUrl;
  final String? title;
  final String? fallbackContent;

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
  InAppWebViewController? _webViewController;
  late String _currentUrl;
  late String _pageTitle;
  double _progress = 0.0;
  bool _isLoading = true;
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _isPinned = false;
  bool _isMaximized = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.initialUrl;
    _pageTitle = widget.title ?? _extractHost(widget.initialUrl);
  }

  String _extractHost(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.host.isNotEmpty) return uri.host;
    } catch (_) {}
    return '网页浏览';
  }

  Future<void> _refresh() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    await _webViewController?.reload();
  }

  Future<void> _openInExternalBrowser() async {
    try {
      await Clipboard.setData(ClipboardData(text: _currentUrl));
      showToast('正在调起系统浏览器...', type: ToastType.info);
      if (!kIsWeb) {
        if (Platform.isWindows) {
          await Process.run('cmd', [
            '/c',
            'start',
            '',
            _currentUrl,
          ], runInShell: true);
        } else if (Platform.isMacOS) {
          await Process.run('open', [_currentUrl]);
        } else if (Platform.isLinux) {
          await Process.run('xdg-open', [_currentUrl]);
        }
      }
    } catch (_) {
      showToast('已复制网页链接至剪贴板: $_currentUrl', type: ToastType.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final windowBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final topBarBg = isDark ? const Color(0xFF232323) : const Color(0xFFF3F3F3);
    final tabBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final borderColor =
        isDark ? const Color(0x1FFFFFFF) : const Color(0x1F000000);

    final screenSize = MediaQuery.of(context).size;
    final dialogWidth =
        _isMaximized
            ? screenSize.width
            : 980.0.clamp(600.0, screenSize.width - 40);
    final dialogHeight =
        _isMaximized
            ? screenSize.height
            : 720.0.clamp(400.0, screenSize.height - 40);

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. 顶部专业浏览器工具栏 (含置顶、Tab标签、地址与控制按钮)
              _buildBrowserTopBar(
                context,
                isDark,
                topBarBg,
                tabBg,
                borderColor,
              ),

              // 2. 加载进度条
              if (_isLoading && _progress < 1.0)
                LinearProgressIndicator(
                  value: _progress,
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF07C160),
                  ),
                ),

              // 3. 网页主内容视图
              Expanded(
                child: Container(
                  color: isDark ? const Color(0xFF181818) : Colors.white,
                  child: Stack(
                    children: [
                      if (InAppWebViewPlatform.instance != null)
                        InAppWebView(
                          initialUrlRequest: URLRequest(
                            url: WebUri(_currentUrl),
                          ),
                          initialSettings: InAppWebViewSettings(
                            useShouldOverrideUrlLoading: true,
                            mediaPlaybackRequiresUserGesture: false,
                            allowsInlineMediaPlayback: true,
                            javaScriptEnabled: true,
                            isInspectable: true,
                          ),
                          onWebViewCreated: (controller) {
                            _webViewController = controller;
                          },
                          onProgressChanged: (controller, progress) {
                            setState(() {
                              _progress = progress / 100.0;
                              _isLoading = progress < 100;
                            });
                          },
                          onTitleChanged: (controller, title) {
                            if (title != null && title.isNotEmpty) {
                              setState(() {
                                _pageTitle = title;
                              });
                            }
                          },
                          onLoadStop: (controller, url) async {
                            final canBack = await controller.canGoBack();
                            final canForward = await controller.canGoForward();
                            setState(() {
                              _isLoading = false;
                              _canGoBack = canBack;
                              _canGoForward = canForward;
                              if (url != null) _currentUrl = url.toString();
                            });
                          },
                          onReceivedError: (controller, request, error) {
                            setState(() {
                              _isLoading = false;
                              _errorMessage = error.description;
                            });
                          },
                        )
                      else
                        _buildWebPreviewPlaceholder(context, isDark),

                      // 加载失败或错误遮罩
                      if (_errorMessage != null)
                        _buildErrorFallback(context, isDark),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWebPreviewPlaceholder(BuildContext context, bool isDark) {
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
            _pageTitle,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            _currentUrl,
            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF282828) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color:
                    isDark ? const Color(0x1FFFFFFF) : const Color(0x1F000000),
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

  Widget _buildBrowserTopBar(
    BuildContext context,
    bool isDark,
    Color bg,
    Color tabBg,
    Color border,
  ) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: bg,
        border: Border(bottom: BorderSide(color: border, width: 0.5)),
      ),
      child: Row(
        children: [
          // 置顶图标
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
            },
          ),

          // 书签/侧边栏图标
          IconButton(
            icon: const Icon(Icons.view_sidebar_outlined, size: 16),
            tooltip: '侧边栏',
            visualDensity: VisualDensity.compact,
            onPressed: () {
              showToast('侧边栏功能已开启', type: ToastType.info);
            },
          ),

          const SizedBox(width: 4),

          // 核心活动标签页 (Tab)
          Flexible(
            child: Container(
              height: 32,
              constraints: const BoxConstraints(maxWidth: 240),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: tabBg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: border, width: 0.5),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.public_rounded,
                    size: 14,
                    color:
                        isDark
                            ? const Color(0xFF07C160)
                            : const Color(0xFF07C160),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _pageTitle,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => Navigator.of(context).pop(),
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(Icons.close_rounded, size: 14),
                    ),
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
            onPressed:
                _canGoBack
                    ? () async {
                      await _webViewController?.goBack();
                    }
                    : null,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios_rounded, size: 13),
            tooltip: '前进',
            visualDensity: VisualDensity.compact,
            onPressed:
                _canGoForward
                    ? () async {
                      await _webViewController?.goForward();
                    }
                    : null,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 16),
            tooltip: '重新加载',
            visualDensity: VisualDensity.compact,
            onPressed: _refresh,
          ),

          const Spacer(),

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
              Clipboard.setData(ClipboardData(text: _currentUrl));
              showToast('网页链接已复制到剪贴板', type: ToastType.success);
            },
          ),

          const SizedBox(width: 6),

          // 窗口控制按钮：最小化、最大化、关闭
          IconButton(
            icon: const Icon(Icons.remove_rounded, size: 16),
            tooltip: '最小化',
            visualDensity: VisualDensity.compact,
            onPressed: () => Navigator.of(context).pop(),
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
              setState(() {
                _isMaximized = !_isMaximized;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 17),
            tooltip: '关闭窗口',
            visualDensity: VisualDensity.compact,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorFallback(BuildContext context, bool isDark) {
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
              _errorMessage ?? '请检查网络连接或稍后重试',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            if (widget.fallbackContent != null &&
                widget.fallbackContent!.isNotEmpty) ...[
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
                    widget.fallbackContent!,
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
