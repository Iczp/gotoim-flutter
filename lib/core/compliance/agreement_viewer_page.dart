import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../browser/browser_more_sheet.dart';

/// Fullscreen document reader for User Agreements and Privacy Policies.
///
/// Supports online network WebView browsing with progress bar and
/// fallback to local full-text view with scrollable text selection.
class AgreementViewerPage extends StatefulWidget {
  const AgreementViewerPage({
    required this.title,
    required this.content,
    this.url,
    this.initialMode = AgreementViewMode.webView,
    super.key,
  });

  final String title;
  final String content;
  final String? url;
  final AgreementViewMode initialMode;

  @override
  State<AgreementViewerPage> createState() => _AgreementViewerPageState();
}

enum AgreementViewMode {
  webView,
  pureText,
}

class _AgreementViewerPageState extends State<AgreementViewerPage> {
  late AgreementViewMode _mode;
  InAppWebViewController? _webController;
  double _progress = 0.0;
  bool _isLoading = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    final hasValidUrl = widget.url != null && widget.url!.trim().isNotEmpty;
    // On web or platforms where WebView might not be available or no URL provided, default to pureText
    if (kIsWeb || !hasValidUrl) {
      _mode = AgreementViewMode.pureText;
    } else {
      _mode = widget.initialMode;
    }
  }

  void _toggleMode() {
    setState(() {
      _mode = _mode == AgreementViewMode.webView
          ? AgreementViewMode.pureText
          : AgreementViewMode.webView;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasValidUrl = widget.url != null && widget.url!.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(widget.title),
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (hasValidUrl && !kIsWeb)
            IconButton(
              icon: Icon(
                _mode == AgreementViewMode.webView
                    ? Icons.article_outlined
                    : Icons.language_rounded,
                size: 20,
              ),
              tooltip: _mode == AgreementViewMode.webView ? '查看纯文本' : '查看网页版',
              onPressed: _toggleMode,
            ),
          if (_mode == AgreementViewMode.webView && hasValidUrl)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              tooltip: '重新加载',
              onPressed: () {
                setState(() {
                  _loadError = null;
                });
                _webController?.reload();
              },
            ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 20),
            tooltip: '复制内容/链接',
            onPressed: () {
              final copyText = _mode == AgreementViewMode.webView && hasValidUrl
                  ? widget.url!
                  : '${widget.title}\n\n${widget.content}';
              Clipboard.setData(ClipboardData(text: copyText));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _mode == AgreementViewMode.webView && hasValidUrl
                          ? '协议链接已复制到剪贴板'
                          : '协议内容已复制到剪贴板',
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_horiz_rounded, size: 24),
            tooltip: '更多',
            onPressed: () {
              showBrowserMoreSheet(
                context,
                url: widget.url ?? '',
                title: widget.title,
                onRefresh: _mode == AgreementViewMode.webView && hasValidUrl
                    ? () {
                        setState(() => _loadError = null);
                        _webController?.reload();
                      }
                    : null,
                onToggleMode: hasValidUrl && !kIsWeb ? _toggleMode : null,
                toggleModeLabel: _mode == AgreementViewMode.webView
                    ? '查看纯文本'
                    : '查看网页版',
                toggleModeIcon: _mode == AgreementViewMode.webView
                    ? Icons.article_outlined
                    : Icons.language_rounded,
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (_mode == AgreementViewMode.webView && _isLoading)
              LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                minHeight: 2.5,
                backgroundColor: Colors.transparent,
              ),
            Expanded(
              child: _mode == AgreementViewMode.webView && hasValidUrl && !kIsWeb
                  ? _buildWebView(context)
                  : _buildPureTextView(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebView(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded, size: 48, color: colorScheme.error),
              const SizedBox(height: 16),
              Text(
                '网络协议页面加载失败',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _loadError!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _loadError = null;
                        _mode = AgreementViewMode.pureText;
                      });
                    },
                    icon: const Icon(Icons.article_outlined, size: 18),
                    label: const Text('查看离线文本'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: () {
                      setState(() {
                        _loadError = null;
                      });
                      _webController?.reload();
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('重试加载'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(widget.url!)),
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
      },
      onLoadStart: (controller, url) {
        if (mounted) {
          setState(() {
            _isLoading = true;
            _loadError = null;
          });
        }
      },
      onProgressChanged: (controller, progress) {
        if (mounted) {
          setState(() {
            _progress = progress / 100.0;
            if (progress >= 100) {
              _isLoading = false;
            }
          });
        }
      },
      onLoadStop: (controller, url) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      },
      onReceivedError: (controller, request, error) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _loadError = error.description;
          });
        }
      },
      onReceivedHttpError: (controller, request, errorResponse) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _loadError = 'HTTP 错误: ${errorResponse.statusCode}';
          });
        }
      },
    );
  }

  Widget _buildPureTextView(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bottomSafePadding = MediaQuery.paddingOf(context).bottom;

    return SelectionArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 24, 20, bottomSafePadding + 48),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '生效日期：2026年9月 · 版本：v1.0',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
                if (widget.url != null && widget.url!.isNotEmpty) ...[
                  const Spacer(),
                  Text(
                    '离线完整版',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            Text(
              widget.content,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.7,
                color: colorScheme.onSurface.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(height: 36),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 32,
                    height: 1,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      '已滑动至协议底部',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  Container(
                    width: 32,
                    height: 1,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
