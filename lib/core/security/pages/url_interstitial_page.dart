import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../browser/app_webview_page.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/desktop_dialog.dart';
import '../url_security_level.dart';
import '../url_security_service.dart';
import '../widgets/appeal_dialog.dart';
import '../widgets/report_dialog.dart';

/// 类似微信官方的高保真外链风险警示中转页与强力阻断拦截页
///
/// 遵循单屏舒适呈现原则（One-Screen Presentation）：
/// - 超长 URL 智能截断折叠（默认最多 2 行，可一键展开/收起）；
/// - 突出提取展示核心主域名（Domain Hero）；
/// - 优化垂直视口预算，小屏设备零滚动完整展示全部内容与操作；
/// - 提供清晰的“误报申诉 / 申请加白”通道，闭环联动后台工单流。
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

  /// 静态便捷调起中转拦截页
  static Future<void> open(
    BuildContext context, {
    required UrlSecurityCheckResult checkResult,
    String? title,
    String? fallbackContent,
  }) {
    final isDesktop =
        !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    if (isDesktop) {
      if (checkResult.isBlocked) {
        return UrlSecurityService.showDesktopBlockedDialog(
          context,
          checkResult: checkResult,
        );
      }
      return AppWebViewPage.open(
        context,
        url: checkResult.url,
        title: title,
        fallbackContent: fallbackContent,
      );
    }
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
  bool _isUrlExpanded = false;

  @override
  void initState() {
    super.initState();
    // 仅在 warning 状态时开启倒计时
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
    final isDesktop =
        !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    if (isDesktop) {
      Navigator.of(context).pop();
      AppWebViewPage.open(
        context,
        url: widget.checkResult.url,
        title: widget.title,
        fallbackContent: widget.fallbackContent,
      );
      return;
    }
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
    showToast('链接已复制到剪贴板', type: ToastType.success);
  }

  void _openAppealDialog() {
    AppealDialog.show(
      context,
      url: widget.checkResult.url,
      domain: widget.checkResult.domain,
      title: widget.title,
    );
  }

  void _openReportDialog() {
    ReportDialog.showForUrl(
      context,
      url: widget.checkResult.url,
      title: widget.title,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isBlocked = widget.checkResult.isBlocked;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF181818) : const Color(0xFFF7F8FA);
    final cardBg = isDark ? const Color(0xFF262626) : Colors.white;

    // 域名展示清洗
    final domain = widget.checkResult.domain.isNotEmpty
        ? widget.checkResult.domain
        : _extractDomain(widget.checkResult.url);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, size: 22),
          tooltip: '关闭',
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.shield_outlined, size: 20),
            tooltip: '申诉与反馈',
            onPressed: _openAppealDialog,
          ),
          IconButton(
            icon: const Icon(Icons.more_horiz_rounded, size: 22),
            tooltip: '更多选项',
            onPressed: () => _showMoreActions(context),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 16,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // 上半部分：提示与风险说明（高度受控紧凑）
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 8),
                        // 盾牌小巧图标 (60x60)
                        _buildShieldIcon(isBlocked),
                        const SizedBox(height: 14),

                        // 主标题
                        Text(
                          isBlocked ? '已停止访问该网页' : '非官方网页访问提示',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.2,
                            color: isBlocked
                                ? const Color(0xFFDC2626)
                                : (isDark ? Colors.white : const Color(0xFF1F2937)),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),

                        // 提示副标题（优先服务端动态下发 message / interceptReason）
                        Text(
                          isBlocked
                              ? (widget.checkResult.interceptReason ??
                                  widget.checkResult.message)
                              : (widget.checkResult.message.isNotEmpty &&
                                      widget.checkResult.message != '官方/受信域名'
                                  ? widget.checkResult.message
                                  : '你即将离开 GotoIM 访问第三方网站。第三方网站非由本平台运营，请注意保护个人财产和隐私安全。'),
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            color: isDark ? Colors.white70 : const Color(0xFF4B5563),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 14),

                        // 目标网址精简卡片（关键一屏优化：Domain Hero + 折叠超长 URL）
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.02),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 头部：域名与状态胶囊
                              Row(
                                children: [
                                  Icon(
                                    isBlocked ? Icons.block_flipped : Icons.language_rounded,
                                    size: 15,
                                    color: isBlocked
                                        ? const Color(0xFFEF4444)
                                        : theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      domain.isNotEmpty ? domain : '外部链接',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : const Color(0xFF111827),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  // 复制小按钮
                                  InkWell(
                                    onTap: _copyUrl,
                                    borderRadius: BorderRadius.circular(4),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.copy_rounded,
                                            size: 13,
                                            color: isDark ? Colors.white54 : Colors.black45,
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            '复制',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDark ? Colors.white54 : Colors.black45,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),

                              // URL 文本展示（默认最多 2 行，避免撑破一屏）
                              GestureDetector(
                                onTap: () => setState(() => _isUrlExpanded = !_isUrlExpanded),
                                child: Text(
                                  widget.checkResult.url,
                                  maxLines: _isUrlExpanded ? null : 2,
                                  overflow: _isUrlExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.35,
                                    fontFamily: 'monospace',
                                    color: isDark ? Colors.white60 : const Color(0xFF4B5563),
                                  ),
                                ),
                              ),

                              // 展开/收起切换与误报申诉提示
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  if (widget.checkResult.url.length > 55)
                                    InkWell(
                                      onTap: () => setState(() => _isUrlExpanded = !_isUrlExpanded),
                                      child: Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          _isUrlExpanded ? '收起链接 ▲' : '展开完整链接 ▼',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                            color: theme.colorScheme.primary,
                                          ),
                                        ),
                                      ),
                                    )
                                  else
                                    const SizedBox.shrink(),
                                  // 卡片内微型申诉引导
                                  InkWell(
                                    onTap: _openAppealDialog,
                                    child: const Padding(
                                      padding: EdgeInsets.only(top: 4),
                                      child: Text(
                                        '网站误报？申请加白',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF07C160),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // 反诈特别提醒紧凑小条（仅在未阻断时展示）
                        if (!isBlocked) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7).withValues(alpha: isDark ? 0.12 : 0.65),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFFF59E0B).withValues(alpha: 0.25),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.security_rounded,
                                  color: Color(0xFFD97706),
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '切勿向陌生账户转账汇款、切勿扫描未知二维码、切勿输入密码与验证码！',
                                    style: TextStyle(
                                      fontSize: 11,
                                      height: 1.35,
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

                    // 底部按钮操作区（高度控制在 130px 左右，保证一屏容纳）
                    Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isBlocked) ...[
                            // 阻断态主操作
                            FilledButton(
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('返回上一页', style: TextStyle(fontSize: 14)),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: const Icon(Icons.verified_outlined, size: 16),
                              label: const Text('网站误报？提交申诉申请解封', style: TextStyle(fontSize: 13)),
                              onPressed: _openAppealDialog,
                            ),
                          ] else ...[
                            // 预警态主操作
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF07C160), // WeChat Green
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: _proceedToInternalWeb,
                              child: Text(
                                _countdown > 0 ? '继续访问 ($_countdown s)' : '继续访问',
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                              label: const Text('在系统浏览器打开', style: TextStyle(fontSize: 13)),
                              onPressed: _openExternalBrowser,
                            ),
                          ],

                          const SizedBox(height: 10),
                          // 底部功能快捷通道单行排列
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              TextButton(
                                onPressed: _copyUrl,
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text('复制网址', style: TextStyle(fontSize: 11.5, color: Colors.grey)),
                              ),
                              const Text('·', style: TextStyle(color: Colors.grey, fontSize: 11)),
                              TextButton(
                                onPressed: _openReportDialog,
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text('投诉举报', style: TextStyle(fontSize: 11.5, color: Colors.grey)),
                              ),
                              const Text('·', style: TextStyle(color: Colors.grey, fontSize: 11)),
                              TextButton(
                                onPressed: _openAppealDialog,
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text(
                                  '误报申诉',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: Color(0xFF07C160),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
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
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFEF4444).withValues(alpha: 0.15),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.gpp_bad_rounded,
          color: Color(0xFFDC2626),
          size: 34,
        ),
      );
    }

    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.gpp_maybe_rounded,
        color: Color(0xFFD97706),
        size: 34,
      ),
    );
  }

  void _showMoreActions(BuildContext context) {
    final isDesktop = (!kIsWeb &&
            (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) ||
        MediaQuery.sizeOf(context).width >= 720;

    if (isDesktop) {
      showDesktopModalDialog<void>(
        context: context,
        title: '更多操作',
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('复制网页链接'),
              onTap: () {
                Navigator.of(context).pop();
                _copyUrl();
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.verified_outlined, color: Color(0xFF07C160)),
              title: const Text('网站误报申诉 / 申请加白'),
              subtitle: const Text(
                '如认为该网站系正规官方业务，可申请加入平台受信白名单',
                style: TextStyle(fontSize: 11),
              ),
              onTap: () {
                Navigator.of(context).pop();
                _openAppealDialog();
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.report_problem_outlined, color: Colors.red),
              title: const Text('投诉与举报违规'),
              subtitle: const Text(
                '涉嫌欺诈、色情、仿冒钓鱼等违规内容举报',
                style: TextStyle(fontSize: 11),
              ),
              onTap: () {
                Navigator.of(context).pop();
                _openReportDialog();
              },
            ),
          ],
        ),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('复制网页链接'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _copyUrl();
                },
              ),
              ListTile(
                leading: const Icon(Icons.verified_outlined, color: Color(0xFF07C160)),
                title: const Text('网站误报申诉 / 申请加白'),
                subtitle: const Text('如认为该网站系正规官方业务，可申请加入平台受信白名单', style: TextStyle(fontSize: 11)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _openAppealDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.report_problem_outlined, color: Colors.red),
                title: const Text('投诉与举报违规'),
                subtitle: const Text('涉嫌欺诈、色情、仿冒钓鱼等违规内容举报', style: TextStyle(fontSize: 11)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _openReportDialog();
                },
              ),
              const Divider(height: 1),
              ListTile(
                title: const Center(
                  child: Text('取消', style: TextStyle(color: Colors.grey)),
                ),
                onTap: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        );
      },
    );
  }

  String _extractDomain(String rawUrl) {
    try {
      final uri = Uri.parse(rawUrl);
      return uri.host;
    } catch (_) {
      return '';
    }
  }
}
