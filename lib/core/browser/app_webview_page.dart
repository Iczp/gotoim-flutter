import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'desktop_browser_window.dart';
import '../floating_window/floating_window.dart';
import '../media/media_preview.dart';
import '../widgets/app_toast.dart';
import 'floating_web_bubble.dart';
import 'browser_more_sheet.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/session/application/session_list_controller.dart';
import '../../features/session/data/models/chat_owner.dart';
import '../config/app_environment.dart';
import '../utils/api_url_resolver.dart';
import '../../app/application_providers.dart';
import '../jsbridge/js_bridge_models.dart';
import '../security/pages/url_interstitial_page.dart';
import '../security/url_security_service.dart';
import '../widgets/app_modal.dart';

/// 解析 CSS 颜色值（支持 hex、rgb、rgba、hsl、hsla 及常见命名颜色）
Color? parseCssColor(String? raw) {
  if (raw == null) return null;
  final str = raw.trim().toLowerCase();
  if (str.isEmpty || str == 'transparent' || str == 'inherit' || str == 'initial') {
    return null;
  }
  if (str == 'black') return Colors.black;
  if (str == 'white') return Colors.white;

  if (str.startsWith('#')) {
    final hex = str.substring(1);
    if (hex.length == 3) {
      final r = hex[0] * 2;
      final g = hex[1] * 2;
      final b = hex[2] * 2;
      final val = int.tryParse('FF$r$g$b', radix: 16);
      return val != null ? Color(val) : null;
    } else if (hex.length == 4) {
      final r = hex[0] * 2;
      final g = hex[1] * 2;
      final b = hex[2] * 2;
      final a = hex[3] * 2;
      final val = int.tryParse('$a$r$g$b', radix: 16);
      return val != null ? Color(val) : null;
    } else if (hex.length == 6) {
      final val = int.tryParse('FF$hex', radix: 16);
      return val != null ? Color(val) : null;
    } else if (hex.length == 8) {
      final rrggbb = hex.substring(0, 6);
      final aa = hex.substring(6, 8);
      final val = int.tryParse('$aa$rrggbb', radix: 16);
      return val != null ? Color(val) : null;
    }
  }

  final rgbMatch = RegExp(
    r'rgba?\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)(?:\s*,\s*([\d.]+))?\s*\)',
  ).firstMatch(str);
  if (rgbMatch != null) {
    final r = int.tryParse(rgbMatch.group(1)!) ?? 0;
    final g = int.tryParse(rgbMatch.group(2)!) ?? 0;
    final b = int.tryParse(rgbMatch.group(3)!) ?? 0;
    final aStr = rgbMatch.group(4);
    final a = aStr != null ? ((double.tryParse(aStr) ?? 1.0) * 255).round().clamp(0, 255) : 255;
    return Color.fromARGB(a, r, g, b);
  }

  final hslMatch = RegExp(
    r'hsla?\s*\(\s*([\d.]+)(?:deg)?\s*,\s*([\d.]+)%\s*,\s*([\d.]+)%(?:\s*,\s*([\d.]+))?\s*\)',
  ).firstMatch(str);
  if (hslMatch != null) {
    final h = (double.tryParse(hslMatch.group(1)!) ?? 0.0) % 360.0;
    final s = ((double.tryParse(hslMatch.group(2)!) ?? 0.0) / 100.0).clamp(0.0, 1.0);
    final l = ((double.tryParse(hslMatch.group(3)!) ?? 0.0) / 100.0).clamp(0.0, 1.0);
    final aStr = hslMatch.group(4);
    final a = aStr != null ? (double.tryParse(aStr) ?? 1.0).clamp(0.0, 1.0) : 1.0;
    return HSLColor.fromAHSL(a, h, s, l).toColor();
  }

  return null;
}

const String _kThemeDetectJs = r'''
(function() {
  function getThemeColor() {
    const metas = document.querySelectorAll('meta[name="theme-color"]');
    for (let i = 0; i < metas.length; i++) {
      const meta = metas[i];
      const media = meta.getAttribute('media');
      if (media) {
        if (window.matchMedia && window.matchMedia(media).matches) {
          const c = meta.getAttribute('content');
          if (c) return c;
        }
      } else {
        const c = meta.getAttribute('content');
        if (c) return c;
      }
    }
    const colorScheme = document.querySelector('meta[name="color-scheme"]');
    if (colorScheme) {
      const val = (colorScheme.getAttribute('content') || '').toLowerCase();
      if (val.includes('dark') && !val.includes('light')) return '#121212';
    }
    const docEl = document.documentElement;
    const body = document.body;
    const isDark = (docEl && (docEl.classList.contains('dark') || docEl.getAttribute('data-theme') === 'dark')) ||
                   (body && (body.classList.contains('dark') || body.getAttribute('data-theme') === 'dark'));
    if (isDark) {
      if (body) {
        const bg = window.getComputedStyle(body).backgroundColor;
        if (bg && bg !== 'rgba(0, 0, 0, 0)' && bg !== 'transparent') return bg;
      }
      return '#121212';
    }
    if (body) {
      const bg = window.getComputedStyle(body).backgroundColor;
      if (bg && bg !== 'rgba(0, 0, 0, 0)' && bg !== 'transparent') return bg;
    }
    if (docEl) {
      const bg = window.getComputedStyle(docEl).backgroundColor;
      if (bg && bg !== 'rgba(0, 0, 0, 0)' && bg !== 'transparent') return bg;
    }
    return null;
  }

  if (!window.__gotoim_theme_observer_installed) {
    window.__gotoim_theme_observer_installed = true;
    function notify() {
      try {
        const c = getThemeColor();
        if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
          window.flutter_inappwebview.callHandler('onHtmlThemeChanged', c);
        }
      } catch (_) {}
    }
    const obs = new MutationObserver(function() { notify(); });
    if (document.head) obs.observe(document.head, { childList: true, subtree: true, attributes: true });
    if (document.documentElement) obs.observe(document.documentElement, { attributes: true, attributeFilter: ['class', 'data-theme'] });
    if (window.matchMedia) {
      try {
        window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', notify);
      } catch (_) {}
    }
  }

  return getThemeColor();
})();
''';

const String _kImagePreviewInjectJs = r'''
(function() {
  if (window.__gotoim_preview_injected) return;
  window.__gotoim_preview_injected = true;

  window.openImage = function(current, urls, index) {
    if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
      if (typeof current === 'object' && current !== null && !Array.isArray(current)) {
        window.flutter_inappwebview.callHandler('openImage', current);
      } else {
        window.flutter_inappwebview.callHandler('openImage', current, urls, index);
      }
    }
  };
  window.previewImage = window.openImage;

  if (!window.wx) window.wx = {};
  if (!window.wx.previewImage) {
    window.wx.previewImage = function(opt) {
      window.openImage(opt);
    };
  }

  // 微信同款：网页内长按 <img> 标签唤起操作菜单与二维码智能识别
  var _imgPressTimer = null;
  document.addEventListener('touchstart', function(e) {
    var t = e.target;
    if (t && t.tagName === 'IMG') {
      var src = t.currentSrc || t.getAttribute('data-src') || t.src;
      if (src && !src.startsWith('data:image/svg')) {
        _imgPressTimer = setTimeout(function() {
          if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
            window.flutter_inappwebview.callHandler('onImageLongPress', { src: src });
          }
        }, 500);
      }
    }
  }, { passive: true });

  document.addEventListener('touchend', function() {
    if (_imgPressTimer) { clearTimeout(_imgPressTimer); _imgPressTimer = null; }
  }, { passive: true });

  document.addEventListener('touchmove', function() {
    if (_imgPressTimer) { clearTimeout(_imgPressTimer); _imgPressTimer = null; }
  }, { passive: true });

  document.addEventListener('contextmenu', function(e) {
    if (e.target && e.target.tagName === 'IMG') {
      var src = e.target.currentSrc || e.target.getAttribute('data-src') || e.target.src;
      if (src && !src.startsWith('data:image/svg')) {
        e.preventDefault();
        if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
          window.flutter_inappwebview.callHandler('onImageLongPress', { src: src });
        }
      }
    }
  });

  // 注入通用扫码快捷方法 (兼容标准与微信格式)
  window.scanCode = function(options) {
    options = options || {};
    if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
      return window.flutter_inappwebview.callHandler('scanCode', options).then(function(res) {
        var content = res && res.result ? res.result.content : (res ? (res.content || '') : '');
        if (typeof options.success === 'function') {
          options.success({ result: content, raw: res });
        }
        return res;
      }).catch(function(err) {
        if (typeof options.fail === 'function') options.fail(err);
        throw err;
      });
    }
    return Promise.reject(new Error('Bridge not ready'));
  };

  if (!window.wx) window.wx = {};
  if (!window.wx.scanQRCode) {
    window.wx.scanQRCode = function(opt) {
      opt = opt || {};
      window.scanCode({
        success: function(res) {
          if (typeof opt.success === 'function') {
            opt.success({ resultStr: res.result });
          }
        },
        fail: opt.fail
      });
    };
  }
})();
''';

/// 类似微信内置浏览器的通用全屏 WebView 页面。
///
/// 功能特性：
/// 1. 顶部微信同款导航条：网页前进/后退、关闭（X）、动态抓取网页 Title；
/// 2. 顶部 WeChat Green (0xFF07C160) 细进度条，加载完成后自动淡出；
/// 3. 右上角「···」（更多）操作菜单，唤起全套微信同款两排底部操作面板；
/// 4. 离线/加载失败友好状态与离线纯文本无缝切换（可用于合规协议等场景）；
/// 5. 网页浮窗能力：可将网页最小化为屏幕贴边浮窗气泡，点击无缝恢复；
/// 6. 提供 [AppWebViewPage.open] 快捷调起方法。
class AppWebViewPage extends ConsumerStatefulWidget {
  const AppWebViewPage({
    required this.initialUrl,
    this.title,
    this.fallbackContent,
    super.key,
  });

  /// 初始打开的网页链接
  final String initialUrl;

  /// 可选的标题（未加载完成时占位使用）
  final String? title;

  /// 降级/离线查看的纯文本（若网络加载失败时可供用户阅读）
  final String? fallbackContent;

  /// 静态调起工具方法
  static Future<void> open(
    BuildContext context, {
    required String url,
    String? title,
    String? fallbackContent,
  }) {
    final isDesktop =
        !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    if (isDesktop) {
      return DesktopBrowserWindow.open(
        context,
        url: url,
        title: title,
        fallbackContent: fallbackContent,
      );
    }
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AppWebViewPage(
          initialUrl: url,
          title: title,
          fallbackContent: fallbackContent,
        ),
      ),
    );
  }

  @override
  ConsumerState<AppWebViewPage> createState() => _AppWebViewPageState();
}

class _AppWebViewPageState extends ConsumerState<AppWebViewPage> {
  InAppWebViewController? _controller;
  late String _currentUrl;
  String _pageTitle = '';
  double _progress = 0.0;
  bool _isLoading = true;
  String? _errorMessage;
  bool _showPureText = false;
  Color? _htmlThemeColor;

  void _applyThemeColor(String? colorStr) {
    if (!mounted) return;
    final color = parseCssColor(colorStr);
    if (_htmlThemeColor != color) {
      setState(() {
        _htmlThemeColor = color;
      });
    }
  }

  Future<void> _detectHtmlTheme() async {
    if (_controller == null || !mounted) return;
    try {
      final res = await _controller!.evaluateJavascript(source: _kThemeDetectJs);
      if (res != null && mounted) {
        _applyThemeColor(res.toString());
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.initialUrl;
    _pageTitle = widget.title ?? '';
    if (InAppWebViewPlatform.instance == null) {
      _isLoading = false;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final manager = ref.read(floatingWindowManagerProvider);
      final floatId = 'web_${widget.initialUrl.hashCode}';
      if (manager.contains(floatId)) {
        manager.close(floatId);
      }
    });
  }

  String get _domain {
    try {
      final uri = Uri.parse(_currentUrl);
      return uri.host.isNotEmpty ? uri.host : '';
    } catch (_) {
      return '';
    }
  }

  void _reload() {
    setState(() {
      _errorMessage = null;
      _isLoading = true;
      _progress = 0.1;
    });
    _controller?.reload();
  }

  void _showMoreMenu() {
    showBrowserMoreSheet(
      context,
      url: _currentUrl,
      title: _pageTitle.isNotEmpty ? _pageTitle : widget.title,
      onRefresh: _showPureText ? null : _reload,
      onToggleMode: widget.fallbackContent != null && widget.fallbackContent!.isNotEmpty
          ? () {
              setState(() {
                _showPureText = !_showPureText;
              });
            }
          : null,
      toggleModeLabel: _showPureText ? '切换网页版' : '查看纯文本',
      toggleModeIcon: _showPureText ? Icons.language_rounded : Icons.article_outlined,
      onMinimizeToFloat: () {
        final nav = Navigator.of(context);
        final manager = ref.read(floatingWindowManagerProvider);
        final targetUrl = _currentUrl;
        final targetTitle = _pageTitle.isNotEmpty ? _pageTitle : widget.title;
        final targetFallback = widget.fallbackContent;
        final floatId = 'web_${targetUrl.hashCode}';

        void restorePage() {
          manager.close(floatId);
          AppWebViewPage.open(
            nav.context,
            url: targetUrl,
            title: targetTitle,
            fallbackContent: targetFallback,
          );
        }

        manager.show(
          id: floatId,
          type: FloatingWindowType.webView,
          options: FloatingWindowOptions.webView(),
          onRestore: restorePage,
          child: FloatingWebBubble(
            url: targetUrl,
            title: targetTitle,
            onRestore: restorePage,
            onClose: () => manager.close(floatId),
          ),
        );
        nav.pop();
        showToast('已缩为浮窗', type: ToastType.success);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 优先响应 HTML meta theme-color / dark 样式，未声明时平滑回退至 App 深浅色
    final Color effectiveBarColor = _htmlThemeColor ?? (isDark ? const Color(0xFF1E1E1E) : Colors.white);
    final bool isBarDark = effectiveBarColor.computeLuminance() < 0.5;
    final Color foregroundColor = isBarDark ? Colors.white : Colors.black87;
    final Color subtitleColor = isBarDark ? Colors.white54 : Colors.black38;

    final displayTitle = _pageTitle.isNotEmpty
        ? _pageTitle
        : (widget.title?.isNotEmpty == true ? widget.title! : '网页');

    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: effectiveBarColor,
        appBar: AppBar(
          backgroundColor: effectiveBarColor,
          foregroundColor: foregroundColor,
          iconTheme: IconThemeData(color: foregroundColor),
          actionsIconTheme: IconThemeData(color: foregroundColor),
          systemOverlayStyle: isBarDark
              ? SystemUiOverlayStyle.light.copyWith(
                  statusBarColor: Colors.transparent,
                  systemNavigationBarColor: effectiveBarColor,
                )
              : SystemUiOverlayStyle.dark.copyWith(
                  statusBarColor: Colors.transparent,
                  systemNavigationBarColor: effectiveBarColor,
                ),
          elevation: 0.5,
          scrolledUnderElevation: 1,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded, size: 24),
            tooltip: '关闭',
            padding: const EdgeInsets.symmetric(horizontal: 8),
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            onPressed: () => Navigator.of(context).pop(),
          ),
          leadingWidth: 48,
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: foregroundColor,
                ),
              ),
              if (_domain.isNotEmpty)
                Text(
                  _domain,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: subtitleColor,
                    fontWeight: FontWeight.normal,
                  ),
                ),
            ],
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.more_horiz_rounded, size: 24),
              tooltip: '更多',
              onPressed: _showMoreMenu,
            ),
          ],
        ),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // ── 微信风格顶部细进度条（加载中显示，加载完毕收起） ───────────────
              if (_isLoading && !_showPureText)
                LinearProgressIndicator(
                  value: _progress > 0.05 ? _progress : null,
                  minHeight: 2.2,
                  backgroundColor: Colors.transparent,
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF07C160)),
                ),

              // ── 正文内容：纯文本 fallback 视图 或 InAppWebView ───────────
              Expanded(
                child: _showPureText && widget.fallbackContent != null
                    ? _buildPureTextView(theme, isDark)
                    : _buildWebView(isDark),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWebView(bool isDark) {
    if (InAppWebViewPlatform.instance == null) {
      if (widget.fallbackContent != null && widget.fallbackContent!.isNotEmpty) {
        return _buildPureTextView(Theme.of(context), isDark);
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.language_rounded,
                size: 48,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
              const SizedBox(height: 12),
              Text(
                _currentUrl,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.wifi_off_rounded,
                size: 64,
                color: isDark ? Colors.white24 : Colors.black26,
              ),
              const SizedBox(height: 16),
              Text(
                '无法打开网页',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white38 : Colors.black45,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('重新加载'),
                  ),
                  if (widget.fallbackContent != null &&
                      widget.fallbackContent!.isNotEmpty)
                    FilledButton.icon(
                      onPressed: () {
                        setState(() => _showPureText = true);
                      },
                      icon: const Icon(Icons.article_outlined, size: 18),
                      label: const Text('查看离线内容'),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(_currentUrl)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        databaseEnabled: true,
        cacheEnabled: true,
        allowsInlineMediaPlayback: true,
        mediaPlaybackRequiresUserGesture: false,
        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        useShouldOverrideUrlLoading: false,
        useOnDownloadStart: true,
        supportZoom: true,
        builtInZoomControls: true,
        displayZoomControls: false,
        javaScriptCanOpenWindowsAutomatically: true,
        safeBrowsingEnabled: false,
        applicationNameForUserAgent: 'GotoIM/1.0.0',
      ),
      onWebViewCreated: (controller) {
        _controller = controller;

        // 统一主信道：GotoIMBridge (处理标准 JSON-RPC 格式调用)
        controller.addJavaScriptHandler(
          handlerName: 'GotoIMBridge',
          callback: (args) async {
            if (args.isEmpty || args[0] == null) return null;
            final raw = args[0].toString();
            try {
              // 安全风控沙箱：非官方受信白名单域名，阻断调用特权 Native JSBridge 敏感接口
              final securityService = ref.read(urlSecurityServiceProvider);
              if (!securityService.isTrustedDomain(_currentUrl)) {
                debugPrint('[GotoIMBridge] 阻断非受信任域名的 Native JSBridge 调用: $_currentUrl');
                return jsonEncode({
                  'success': false,
                  'error': {
                    'code': 'UNAUTHORIZED_ORIGIN',
                    'message': '当前网页未获得 GotoIM Native JSBridge 权限',
                  },
                });
              }
              final dispatcher = ref.read(jsApiDispatcherProvider);
              return await dispatcher.handleRaw(raw);
            } catch (e) {
              debugPrint('[GotoIMBridge] error: $e');
              return null;
            }
          },
        );

        // 统一图片预览处理器（支持 openImage、previewImage、media.previewImage）
        Future<bool> handlePreviewImage(List<dynamic> args) async {
          if (args.isEmpty || !mounted) return false;
          try {
            final dispatcher = ref.read(jsApiDispatcherProvider);
            final data = <String, dynamic>{};
            if (args[0] is Map) {
              data.addAll(Map<String, dynamic>.from(args[0] as Map));
            } else if (args[0] is String) {
              data['current'] = args[0].toString();
              if (args.length > 1 && args[1] is List) {
                data['urls'] = (args[1] as List).map((e) => e.toString()).toList();
              }
              if (args.length > 2 && args[2] is int) {
                data['index'] = args[2];
              }
            } else if (args[0] is List) {
              data['urls'] = (args[0] as List).map((e) => e.toString()).toList();
              if (args.length > 1 && args[1] != null) {
                if (args[1] is int) {
                  data['index'] = args[1];
                } else if (args[1] is String) {
                  data['current'] = args[1].toString();
                }
              }
            }

            // URL 补全规范化（支持相对路径、协议相对路径、data:image 等）
            String normalizeUrl(String raw) {
              final trimmed = raw.trim();
              if (trimmed.isEmpty ||
                  trimmed.startsWith('data:image/') ||
                  trimmed.startsWith('file:') ||
                  trimmed.startsWith('http://') ||
                  trimmed.startsWith('https://')) {
                return trimmed;
              }
              if (trimmed.startsWith('//')) {
                final pageUri = Uri.tryParse(_currentUrl);
                final scheme = (pageUri != null && pageUri.scheme.isNotEmpty)
                    ? pageUri.scheme
                    : 'https';
                return '$scheme:$trimmed';
              }
              final pageUri = Uri.tryParse(_currentUrl);
              if (pageUri != null && pageUri.hasScheme && pageUri.host.isNotEmpty) {
                try {
                  return pageUri.resolve(trimmed).toString();
                } catch (_) {}
              }
              final env = ref.read(appEnvironmentProvider);
              return resolveApiUrl(trimmed, env.apiBaseUrl);
            }

            if (data['current'] != null) {
              data['current'] = normalizeUrl(data['current'].toString());
            }
            if (data['urls'] is List) {
              data['urls'] = (data['urls'] as List)
                  .map((e) => normalizeUrl(e?.toString() ?? ''))
                  .where((e) => e.isNotEmpty)
                  .toList();
            }

            final resp = await dispatcher.dispatch(
              JsBridgeRequest(
                id: 'shim_open_image_${DateTime.now().millisecondsSinceEpoch}',
                action: 'media.previewImage',
                data: data,
              ),
            );
            return resp.success;
          } catch (e) {
            debugPrint('[WebViewBridge] previewImage error: $e');
            return false;
          }
        }

        controller.addJavaScriptHandler(
          handlerName: 'openImage',
          callback: handlePreviewImage,
        );
        controller.addJavaScriptHandler(
          handlerName: 'previewImage',
          callback: handlePreviewImage,
        );
        controller.addJavaScriptHandler(
          handlerName: 'media.previewImage',
          callback: handlePreviewImage,
        );

        // 网页内直接长按图片处理器（微信同款识别二维码与快捷操作）
        controller.addJavaScriptHandler(
          handlerName: 'onImageLongPress',
          callback: (args) async {
            if (args.isEmpty || !mounted) return false;
            try {
              final map = args[0] is Map ? (args[0] as Map) : <dynamic, dynamic>{};
              final rawSrc = map['src']?.toString() ?? '';
              if (rawSrc.isEmpty) return false;

              String normalizeUrl(String raw) {
                final trimmed = raw.trim();
                if (trimmed.isEmpty ||
                    trimmed.startsWith('data:image/') ||
                    trimmed.startsWith('file:') ||
                    trimmed.startsWith('http://') ||
                    trimmed.startsWith('https://')) {
                  return trimmed;
                }
                if (trimmed.startsWith('//')) {
                  final pageUri = Uri.tryParse(_currentUrl);
                  final scheme = (pageUri != null && pageUri.scheme.isNotEmpty)
                      ? pageUri.scheme
                      : 'https';
                  return '$scheme:$trimmed';
                }
                final pageUri = Uri.tryParse(_currentUrl);
                if (pageUri != null && pageUri.hasScheme && pageUri.host.isNotEmpty) {
                  try {
                    return pageUri.resolve(trimmed).toString();
                  } catch (_) {}
                }
                final env = ref.read(appEnvironmentProvider);
                return resolveApiUrl(trimmed, env.apiBaseUrl);
              }

              final src = normalizeUrl(rawSrc);
              Uint8List? dataBytes;
              if (src.startsWith('data:image/')) {
                final commaIdx = src.indexOf(',');
                if (commaIdx != -1) {
                  try {
                    dataBytes = base64Decode(src.substring(commaIdx + 1));
                  } catch (_) {}
                }
              }

              final item = MediaPreviewItem(
                id: src,
                messageId: 'h5_img_${src.hashCode}',
                type: MediaPreviewType.image,
                source: src,
                bytes: dataBytes,
                heroTag: 'h5-image-$src',
              );

              await MediaPreview.showActionSheet(
                context,
                ref: ref,
                item: item,
                onShare: () async {
                  await Clipboard.setData(ClipboardData(text: src));
                  showToast('图片链接已复制到剪贴板', type: ToastType.success);
                },
              );
              return true;
            } catch (e) {
              debugPrint('[WebViewBridge] onImageLongPress error: $e');
              return false;
            }
          },
        );

        // 统一扫码处理器（支持 H5/JS-SDK/微信直接调用）
        controller.addJavaScriptHandler(
          handlerName: 'scanCode',
          callback: (args) async {
            try {
              final dispatcher = ref.read(jsApiDispatcherProvider);
              final map = args.isNotEmpty && args[0] is Map
                  ? (args[0] as Map).cast<String, dynamic>()
                  : <String, dynamic>{};
              final resp = await dispatcher.dispatch(
                JsBridgeRequest(
                  id: 'shim_scan_code_${DateTime.now().millisecondsSinceEpoch}',
                  action: 'scan.scanCode',
                  data: map,
                ),
              );
              return resp.data;
            } catch (e) {
              debugPrint('[WebViewBridge] scanCode error: $e');
              return null;
            }
          },
        );

        // 统一视频预览处理器（支持 openVideo、previewVideo、media.previewVideo）
        Future<bool> handlePreviewVideo(List<dynamic> args) async {
          if (args.isEmpty || !mounted) return false;
          try {
            final dispatcher = ref.read(jsApiDispatcherProvider);
            final data = <String, dynamic>{};
            if (args[0] is Map) {
              data.addAll(Map<String, dynamic>.from(args[0] as Map));
            } else if (args[0] is String) {
              data['url'] = args[0].toString();
              if (args.length > 1 && args[1] != null) {
                data['poster'] = args[1].toString();
              }
            }

            String normalizeUrl(String raw) {
              final trimmed = raw.trim();
              if (trimmed.isEmpty ||
                  trimmed.startsWith('file:') ||
                  trimmed.startsWith('http://') ||
                  trimmed.startsWith('https://')) {
                return trimmed;
              }
              if (trimmed.startsWith('//')) {
                final pageUri = Uri.tryParse(_currentUrl);
                final scheme = (pageUri != null && pageUri.scheme.isNotEmpty)
                    ? pageUri.scheme
                    : 'https';
                return '$scheme:$trimmed';
              }
              final pageUri = Uri.tryParse(_currentUrl);
              if (pageUri != null && pageUri.hasScheme && pageUri.host.isNotEmpty) {
                try {
                  return pageUri.resolve(trimmed).toString();
                } catch (_) {}
              }
              final env = ref.read(appEnvironmentProvider);
              return resolveApiUrl(trimmed, env.apiBaseUrl);
            }

            if (data['url'] != null) {
              data['url'] = normalizeUrl(data['url'].toString());
            }
            if (data['poster'] != null) {
              data['poster'] = normalizeUrl(data['poster'].toString());
            }

            final resp = await dispatcher.dispatch(
              JsBridgeRequest(
                id: 'shim_open_video_${DateTime.now().millisecondsSinceEpoch}',
                action: 'media.previewVideo',
                data: data,
              ),
            );
            return resp.success;
          } catch (e) {
            debugPrint('[WebViewBridge] openVideo error: $e');
            return false;
          }
        }

        controller.addJavaScriptHandler(
          handlerName: 'openVideo',
          callback: handlePreviewVideo,
        );
        controller.addJavaScriptHandler(
          handlerName: 'previewVideo',
          callback: handlePreviewVideo,
        );
        controller.addJavaScriptHandler(
          handlerName: 'media.previewVideo',
          callback: handlePreviewVideo,
        );

        controller.addJavaScriptHandler(
          handlerName: 'close',
          callback: (_) {
            if (mounted) {
              Navigator.of(context).pop();
            }
          },
        );
        controller.addJavaScriptHandler(
          handlerName: 'setTitle',
          callback: (args) {
            if (args.isNotEmpty && args[0] != null && mounted) {
              final newTitle = args[0].toString().trim();
              if (newTitle.isNotEmpty && _pageTitle != newTitle) {
                setState(() {
                  _pageTitle = newTitle;
                });
              }
            }
          },
        );
        controller.addJavaScriptHandler(
          handlerName: 'onHtmlThemeChanged',
          callback: (args) {
            if (args.isNotEmpty && args[0] != null) {
              _applyThemeColor(args[0].toString());
            } else {
              _applyThemeColor(null);
            }
          },
        );
        controller.addJavaScriptHandler(
          handlerName: 'getAppContext',
          callback: (_) async {
            try {
              final isDark = mounted && Theme.of(context).brightness == Brightness.dark;
              final tokenStorage = ref.read(tokenStorageProvider);
              final token = await tokenStorage.readAccessToken();
              final auth = ref.read(authControllerProvider);
              final env = ref.read(appEnvironmentProvider);
              final apiBaseUrl = env.apiBaseUrl;
              final sessionList = ref.read(sessionListControllerProvider);
              final currentOwner = sessionList.currentOwner;
              final owners = sessionList.owners;

              return <String, dynamic>{
                'token': token,
                'theme': isDark ? 'dark' : 'light',
                'user': auth.currentUser != null
                    ? <String, dynamic>{
                        'id': auth.currentUser!.id,
                        'userName': auth.currentUser!.userName,
                        'name': auth.currentUser!.name,
                        'email': auth.currentUser!.email,
                        'phoneNumber': auth.currentUser!.phoneNumber,
                      }
                    : null,
                'currentChatObject': currentOwner != null
                    ? <String, dynamic>{
                        'id': currentOwner.id,
                        'name': currentOwner.name,
                        'portrait': resolveApiUrl(currentOwner.imageUrl, apiBaseUrl),
                        'objectType': currentOwner.typeDescription,
                      }
                    : null,
                'availableChatObjects': owners
                    .map((o) => <String, dynamic>{
                          'id': o.id,
                          'name': o.name,
                          'portrait': resolveApiUrl(o.imageUrl, apiBaseUrl),
                          'objectType': o.typeDescription,
                        })
                    .toList(),
              };
            } catch (e) {
              debugPrint('[WebViewBridge] getAppContext error: $e');
              return null;
            }
          },
        );
        controller.addJavaScriptHandler(
          handlerName: 'switchChatObject',
          callback: (args) async {
            try {
              if (args.isNotEmpty && args[0] != null) {
                final target = args[0] is Map ? args[0] as Map : {};
                final targetId = int.tryParse(target['id']?.toString() ?? '') ?? 0;
                final sessionList = ref.read(sessionListControllerProvider);
                final targetOwner = sessionList.owners.cast<ChatOwner?>().firstWhere(
                      (o) => o?.id == targetId,
                      orElse: () => null,
                    );
                if (targetOwner != null) {
                  await sessionList.selectOwner(targetOwner);
                  return true;
                }
              }
            } catch (e) {
              debugPrint('[WebViewBridge] switchChatObject error: $e');
            }
            return false;
          },
        );
      },
      onLoadStart: (controller, url) async {
        if (!mounted) return;
        setState(() {
          _isLoading = true;
          _htmlThemeColor = null;
          if (url != null) {
            _currentUrl = url.toString();
          }
        });
        if (url != null) {
          final targetStr = url.toString();
          final securityService = ref.read(urlSecurityServiceProvider);
          final res = await securityService.checkUrl(targetStr);
          if (res.isBlocked && mounted) {
            // 阻断重定向：停止加载并转入红盾阻断拦截页
            controller.stopLoading();
            Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => UrlInterstitialPage(checkResult: res),
              ),
            );
          }
        }
      },
      onDownloadStarting: (controller, downloadRequest) async {
        final downloadUrl = downloadRequest.url.toString();
        final securityService = ref.read(urlSecurityServiceProvider);
        if (securityService.isDangerousDownload(downloadUrl)) {
          final confirmed = await showConfirmModal(
            context: context,
            title: '文件下载安全提示',
            message:
                '网页正尝试下载应用安装包/可执行文件：\n$downloadUrl\n\n来源不明的安装文件可能存在病毒木马或恶意扣费，是否仍使用系统浏览器继续下载？',
            confirmText: '风险自担，继续',
            cancelText: '取消下载',
          );
          if (!confirmed) {
            return DownloadStartResponse(handled: true);
          }
        }
        try {
          await InAppBrowser.openWithSystemBrowser(url: downloadRequest.url);
        } catch (e) {
          showToast('无法启动下载: $e', type: ToastType.error);
        }
        return DownloadStartResponse(handled: true);
      },
      onProgressChanged: (controller, progress) {
        if (!mounted) return;
        setState(() {
          _progress = progress / 100.0;
        });
      },
      onTitleChanged: (controller, title) {
        if (!mounted) return;
        if (title != null && title.isNotEmpty) {
          setState(() {
            _pageTitle = title;
          });
        }
        _detectHtmlTheme();
      },
      onLoadStop: (controller, url) async {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          if (url != null) {
            _currentUrl = url.toString();
          }
        });
        _detectHtmlTheme();
        try {
          await controller.evaluateJavascript(source: _kImagePreviewInjectJs);
        } catch (_) {}
      },
      onReceivedError: (controller, request, error) {
        if (!mounted) return;
        // 仅主框架错误才阻断显示错误页，避免第三方统计/埋点或子资源 404 导致整屏阻断
        if (request.isForMainFrame ?? true) {
          setState(() {
            _isLoading = false;
            _errorMessage = error.description;
          });
        }
      },
      onConsoleMessage: (controller, consoleMessage) {
        final level = consoleMessage.messageLevel;
        final msg = consoleMessage.message;
        if (level == ConsoleMessageLevel.ERROR) {
          debugPrint('\x1B[31m[H5:ERROR] $msg\x1B[0m');
        } else if (level == ConsoleMessageLevel.WARNING) {
          debugPrint('\x1B[33m[H5:WARN] $msg\x1B[0m');
        } else {
          debugPrint('[H5:LOG] $msg');
        }
      },
    );
  }

  Widget _buildPureTextView(ThemeData theme, bool isDark) {
    final bottomSafePadding = MediaQuery.of(context).padding.bottom;
    return SelectionArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, bottomSafePadding + 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.title != null && widget.title!.isNotEmpty) ...[
              Text(
                widget.title!,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              widget.fallbackContent!,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.7,
                fontSize: 14.5,
                color: isDark ? Colors.white70 : const Color(0xFF333333),
              ),
            ),
            const SizedBox(height: 32),
            Center(
              child: Text(
                '—— 已滑动至文档底部 ——',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isDark ? Colors.white30 : Colors.black26,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
