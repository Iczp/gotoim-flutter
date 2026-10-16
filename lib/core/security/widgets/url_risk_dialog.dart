import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../widgets/app_toast.dart';
import '../url_security_level.dart';
import 'appeal_dialog.dart';
import 'report_dialog.dart';

/// URL 风险操作选择结果
enum UrlRiskDialogAction {
  /// 用户取消
  cancel,

  /// 在内置安全受限 WebView 中继续打开
  openInternal,

  /// 调用系统默认外部浏览器打开
  openExternal,
}

/// 第三方外部链接风险警示弹窗（Phase 1 基础拦截对话框）
class UrlRiskDialog extends StatelessWidget {
  const UrlRiskDialog({
    required this.checkResult,
    super.key,
  });

  final UrlSecurityCheckResult checkResult;

  static Future<UrlRiskDialogAction?> show(
    BuildContext context, {
    required UrlSecurityCheckResult checkResult,
  }) {
    return showDialog<UrlRiskDialogAction>(
      context: context,
      barrierDismissible: true,
      builder: (_) => UrlRiskDialog(checkResult: checkResult),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.gpp_maybe_rounded,
              color: Color(0xFFF59E0B),
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              '第三方网页访问提示',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),
          // 目标域名胶囊标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.language_rounded,
                  size: 15,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    checkResult.domain.isNotEmpty
                        ? checkResult.domain
                        : checkResult.url,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            checkResult.message,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: isDark ? Colors.white70 : const Color(0xFF4B5563),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7).withValues(alpha: isDark ? 0.15 : 0.6),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                width: 0.8,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xFFD97706),
                  size: 16,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '谨防电信网络诈骗、虚假中奖、刷单返利！切勿轻易向陌生账户转账或输入银行卡支付密码。',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // 完整链接预览（可点击复制）
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: checkResult.url));
              showToast('链接已复制到剪贴板', type: ToastType.success);
            },
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      checkResult.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.primary.withValues(alpha: 0.8),
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.copy_rounded,
                    size: 13,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
          // 申诉与投诉入口
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.verified_outlined, size: 13, color: Color(0xFF07C160)),
                label: const Text(
                  '误报申诉',
                  style: TextStyle(fontSize: 11.5, color: Color(0xFF07C160)),
                ),
                onPressed: () {
                  Navigator.of(context).pop(UrlRiskDialogAction.cancel);
                  AppealDialog.show(context, url: checkResult.url, domain: checkResult.domain);
                },
              ),
              const SizedBox(width: 8),
              const Text('·', style: TextStyle(color: Colors.grey, fontSize: 11)),
              const SizedBox(width: 8),
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.flag_outlined, size: 13, color: Colors.grey),
                label: const Text(
                  '投诉此链接',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey),
                ),
                onPressed: () {
                  Navigator.of(context).pop(UrlRiskDialogAction.cancel);
                  ReportDialog.showForUrl(context, url: checkResult.url);
                },
              ),
            ],
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(UrlRiskDialogAction.cancel),
          child: const Text('取消', style: TextStyle(color: Colors.grey)),
        ),
        OutlinedButton(
          onPressed: () async {
            Navigator.of(context).pop(UrlRiskDialogAction.openExternal);
            try {
              final uri = WebUri(checkResult.url);
              await InAppBrowser.openWithSystemBrowser(url: uri);
            } catch (e) {
              showToast('无法启动系统浏览器: $e', type: ToastType.error);
            }
          },
          child: const Text('外部浏览器打开'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF07C160), // WeChat Green
          ),
          onPressed: () =>
              Navigator.of(context).pop(UrlRiskDialogAction.openInternal),
          child: const Text('继续访问'),
        ),
      ],
    );
  }
}
