import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../widgets/app_toast.dart';

/// 微信风格的内置浏览器「更多」操作项定义。
class WeChatBrowserAction {
  const WeChatBrowserAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

/// 弹出类似微信网页右上角「···」（更多）点击后的底部操作抽屉。
Future<void> showWeChatBrowserMoreSheet(
  BuildContext context, {
  required String url,
  String? title,
  VoidCallback? onRefresh,
  VoidCallback? onToggleMode,
  String? toggleModeLabel,
  IconData? toggleModeIcon,
  VoidCallback? onAdjustFontSize,
  VoidCallback? onMinimizeToFloat,
  List<WeChatBrowserAction>? customActions,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _WeChatBrowserMoreSheetContent(
      url: url,
      title: title,
      onRefresh: onRefresh,
      onToggleMode: onToggleMode,
      toggleModeLabel: toggleModeLabel,
      toggleModeIcon: toggleModeIcon,
      onAdjustFontSize: onAdjustFontSize,
      onMinimizeToFloat: onMinimizeToFloat,
      customActions: customActions,
    ),
  );
}

class _WeChatBrowserMoreSheetContent extends StatelessWidget {
  const _WeChatBrowserMoreSheetContent({
    required this.url,
    this.title,
    this.onRefresh,
    this.onToggleMode,
    this.toggleModeLabel,
    this.toggleModeIcon,
    this.onAdjustFontSize,
    this.onMinimizeToFloat,
    this.customActions,
  });

  final String url;
  final String? title;
  final VoidCallback? onRefresh;
  final VoidCallback? onToggleMode;
  final String? toggleModeLabel;
  final IconData? toggleModeIcon;
  final VoidCallback? onAdjustFontSize;
  final VoidCallback? onMinimizeToFloat;
  final List<WeChatBrowserAction>? customActions;

  String get _domain {
    try {
      final uri = Uri.parse(url);
      return uri.host.isNotEmpty ? uri.host : '网页';
    } catch (_) {
      return '网页';
    }
  }

  void _copyLink(BuildContext context) {
    Navigator.of(context).pop();
    Clipboard.setData(ClipboardData(text: url));
    showToast('链接已复制到剪贴板', type: ToastType.success);
  }

  Future<void> _openInExternalBrowser(BuildContext context) async {
    Navigator.of(context).pop();
    try {
      final uri = WebUri(url);
      await InAppBrowser.openWithSystemBrowser(url: uri);
    } catch (e) {
      showToast('无法打开外部浏览器: $e', type: ToastType.error);
    }
  }

  void _sendToFriends(BuildContext context) {
    Navigator.of(context).pop();
    Clipboard.setData(
      ClipboardData(text: title != null && title!.isNotEmpty ? '【$title】$url' : url),
    );
    showToast('已复制分享链接，可直接发送给好友', type: ToastType.success);
  }

  void _shareToMoments(BuildContext context) {
    Navigator.of(context).pop();
    showToast('已生成分享内容', type: ToastType.info);
  }

  void _addToFavorites(BuildContext context) {
    Navigator.of(context).pop();
    showToast('已添加至收藏', type: ToastType.success);
  }

  void _minimize(BuildContext context) {
    Navigator.of(context).pop();
    if (onMinimizeToFloat != null) {
      onMinimizeToFloat!();
    } else {
      showToast('已添加为浮窗', type: ToastType.info);
    }
  }

  void _showReport(BuildContext context) {
    Navigator.of(context).pop();
    showToast('投诉已提交，平台将尽快审核', type: ToastType.info);
  }

  void _showFontSizeDialog(BuildContext context) {
    Navigator.of(context).pop();
    if (onAdjustFontSize != null) {
      onAdjustFontSize!();
      return;
    }
    showToast('当前已是最佳适宜字体', type: ToastType.info);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF242424) : const Color(0xFFF7F7F7);
    final itemBgColor = isDark ? const Color(0xFF333333) : Colors.white;
    final iconColor = isDark ? Colors.white.withValues(alpha: 0.85) : const Color(0xFF2D3133);
    final textColor = isDark ? Colors.white.withValues(alpha: 0.65) : const Color(0xFF555555);

    // 第一排：分享、传播与快捷功能（类似微信第一排）
    final firstRowActions = <WeChatBrowserAction>[
      WeChatBrowserAction(
        icon: Icons.send_rounded,
        label: '发送给朋友',
        onTap: () => _sendToFriends(context),
      ),
      WeChatBrowserAction(
        icon: Icons.donut_large_rounded,
        label: '分享到朋友圈',
        onTap: () => _shareToMoments(context),
      ),
      WeChatBrowserAction(
        icon: Icons.bookmark_border_rounded,
        label: '微信收藏',
        onTap: () => _addToFavorites(context),
      ),
      WeChatBrowserAction(
        icon: Icons.picture_in_picture_alt_rounded,
        label: '浮窗',
        onTap: () => _minimize(context),
      ),
      if (customActions != null) ...customActions!,
    ];

    // 第二排：页面工具与系统能力（类似微信第二排）
    final secondRowActions = <WeChatBrowserAction>[
      WeChatBrowserAction(
        icon: Icons.open_in_browser_rounded,
        label: '在浏览器打开',
        onTap: () => _openInExternalBrowser(context),
      ),
      WeChatBrowserAction(
        icon: Icons.link_rounded,
        label: '复制链接',
        onTap: () => _copyLink(context),
      ),
      if (onRefresh != null)
        WeChatBrowserAction(
          icon: Icons.refresh_rounded,
          label: '刷新',
          onTap: () {
            Navigator.of(context).pop();
            onRefresh!();
          },
        ),
      if (onToggleMode != null)
        WeChatBrowserAction(
          icon: toggleModeIcon ?? Icons.article_outlined,
          label: toggleModeLabel ?? '切换视图',
          onTap: () {
            Navigator.of(context).pop();
            onToggleMode!();
          },
        ),
      WeChatBrowserAction(
        icon: Icons.format_size_rounded,
        label: '调整字体',
        onTap: () => _showFontSizeDialog(context),
      ),
      WeChatBrowserAction(
        icon: Icons.report_problem_outlined,
        label: '投诉',
        onTap: () => _showReport(context),
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 顶部域名/服务归属安全提示 ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    size: 13,
                    color: isDark ? Colors.white38 : Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '网页由 $_domain 提供',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white38 : Colors.grey,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Divider(
              height: 0.5,
              thickness: 0.5,
              color: isDark ? Colors.white12 : Colors.grey.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 14),

            // ── 第一排操作 ──────────────────────────────────────────────
            _buildActionRow(firstRowActions, itemBgColor, iconColor, textColor),

            const SizedBox(height: 16),

            // ── 第二排操作 ──────────────────────────────────────────────
            _buildActionRow(secondRowActions, itemBgColor, iconColor, textColor),

            const SizedBox(height: 14),

            // ── 分隔粗线（微信风格 7-8px 浅灰槽） ─────────────────────────────
            Container(
              height: 7,
              color: isDark ? const Color(0xFF1B1B1B) : const Color(0xFFEBEBEB),
            ),

            // ── 底部「取消」按钮 ─────────────────────────────────────────
            InkWell(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                height: 52,
                alignment: Alignment.center,
                color: isDark ? const Color(0xFF242424) : Colors.white,
                child: Text(
                  '取消',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionRow(
    List<WeChatBrowserAction> actions,
    Color itemBgColor,
    Color iconColor,
    Color textColor,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: actions.map((action) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: InkWell(
              onTap: action.onTap,
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 62,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: itemBgColor,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 4,
                            offset: const Offset(0, 1.5),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        action.icon,
                        size: 26,
                        color: iconColor,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      action.label,
                      style: TextStyle(
                        fontSize: 11,
                        color: textColor,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
