import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../browser/app_webview_page.dart';
import '../../widgets/app_toast.dart';
import '../url_security_level.dart';
import '../widgets/report_dialog.dart';

/// 类似微信官方的高保真非官方外链风险警示中转页与阻断拦截页（Phase 2）
class UrlInterstitialPage extends StatefulWidget {
  const UrlInterstitialPage({
    required this.checkResult,
    this.title,
    this.fallbackContent,
    super.key,
  });

  final UrlSecurityCheckResult checkResult;
  final String? title;
  final String? fallbackContent;

  /// 静态调起中转拦截页
  static Future<void> open(
    BuildContext context, {
    required UrlSecurityCheckResult checkResult,
    String? title,
    String? fallbackContent,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UrlInterstitialPage(
          checkResult: checkResult,
          title: title,
          fallbackContent: fallbackContent,
        ),
      ),
    );
  }

  @override
  State<UrlInterstitialPage> createState() => _UrlInterstitialPageState();
}

class _UrlInterstitialPageState extends State<UrlInterstitialPage> {
  int _countdown = 3;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // 仅在 warning 状态时可选倒计时（或让用户随时可点）
    if (widget.checkResult.isWarning) {
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        if (_countdown > 0) {
          setState(() => _countdown--);
        } else {
          t.cancel();
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _proceedToInternalWeb() {
    // 替换当前中转页，进入安全受限内置 WebView
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => AppWebViewPage(
          initialUrl: widget.checkResult.url,
          title: widget.title,
          fallbackContent: widget.fallbackContent,
        ),
      ),
    );
  }

  Future<void> _openExternalBrowser() async {
    try {
      final uri = WebUri(widget.checkResult.url);
      await InAppBrowser.openWithSystemBrowser(url: uri);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      showToast('无法启动系统浏览器: $e', type: ToastType.error);
    }
  }

  void _copyUrl() {
    Clipboard.setData(ClipboardData(text: widget.checkResult.url));
    showToast('链接已复制', type: ToastType.success);
  }

  @override
  Widget build(BuildContext context) {
    final isBlocked = widget.checkResult.isBlocked;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF7F8FA);
    final cardBg = isDark ? const Color(0xFF2B2B2B) : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: '关闭',
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_horiz_rounded),
            tooltip: '投诉与反馈',
            onPressed: () => ReportDialog.showForUrl(
              context,
              url: widget.checkResult.url,
              title: widget.title,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      children: [
                        const SizedBox(height: 20),
                        // 盾牌大图标
                        _buildShieldIcon(isBlocked),
                        const SizedBox(height: 24),

                        // 主标题
                        Text(
                          isBlocked ? '已停止访问该网页' : '非官方网页访问提示',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.bold,
                            color: isBlocked
                                ? const Color(0xFFDC2626)
                                : (isDark ? Colors.white : const Color(0xFF1F2937)),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),

                        // 提示副标题
                        Text(
                          isBlocked
                              ? (widget.checkResult.interceptReason ??
                                  '据用户投诉及相关法律法规核查，该网页包含违法/诈骗/违规内容。为维护网络安全生态，已全面停止访问。')
                              : '你即将离开 GotoIM 访问第三方网站。第三方网站非由本平台运营，请注意保护财产和个人隐私，防范虚假信息与电信网络诈骗。',
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.55,
                            color: isDark ? Colors.white70 : const Color(0xFF4B5563),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),

                        // 目标域名信息卡片
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.link_rounded,
                                    size: 16,
                                    color: isDark ? Colors.white60 : Colors.black54,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '目标网址：',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? Colors.white60 : Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              SelectableText(
                                widget.checkResult.url,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              if (widget.checkResult.domain.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '所属域名：${widget.checkResult.domain}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? Colors.white38 : Colors.black38,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                        // 反诈特别提醒盒子（若为 warning）
                        if (!isBlocked) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7)
                                  .withValues(alpha: isDark ? 0.15 : 0.7),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.shield_outlined,
                                  color: Color(0xFFD97706),
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '切勿向陌生账户转账汇款、切勿扫描未知二维码、切勿轻易输入账号与支付密码！',
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.4,
                                      color: isDark
                                          ? const Color(0xFFFDE68A)
                                          : const Color(0xFF92400E),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),

                    // 底部按钮操作区
                    Padding(
                      padding: const EdgeInsets.only(top: 32, bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (isBlocked) ...[
                            FilledButton(
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('返回', style: TextStyle(fontSize: 15)),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: () {
                                showToast('申诉已提交，平台安全审核团队将在3个工作日内复核',
                                    type: ToastType.info);
                              },
                              child: const Text('申请恢复访问 (申诉)',
                                  style: TextStyle(fontSize: 14)),
                            ),
                          ] else ...[
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF07C160), // WeChat Green
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: _proceedToInternalWeb,
                              child: Text(
                                _countdown > 0 ? '继续访问 ($_countdown s)' : '继续访问',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                              label: const Text('在系统浏览器打开',
                                  style: TextStyle(fontSize: 14)),
                              onPressed: _openExternalBrowser,
                            ),
                          ],
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              TextButton(
                                onPressed: _copyUrl,
                                child: const Text('复制网址',
                                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                              ),
                              const Text('·', style: TextStyle(color: Colors.grey)),
                              TextButton(
                                onPressed: () => ReportDialog.showForUrl(
                                  context,
                                  url: widget.checkResult.url,
                                  title: widget.title,
                                ),
                                child: const Text('投诉与举报',
                                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildShieldIcon(bool isBlocked) {
    if (isBlocked) {
      return Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFEF4444).withValues(alpha: 0.2),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.gpp_bad_rounded,
          color: Color(0xFFDC2626),
          size: 48,
        ),
      );
    }

    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.gpp_maybe_rounded,
        color: Color(0xFFD97706),
        size: 48,
      ),
    );
  }
}
