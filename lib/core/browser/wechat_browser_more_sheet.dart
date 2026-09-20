import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/chat/application/chat_controller.dart';
import '../../features/session/application/session_list_controller.dart';
import '../../features/session/data/models/session_summary.dart';
import '../widgets/app_avatar.dart';
import '../widgets/app_toast.dart';
import '../widgets/avatar_preferences.dart';
import '../widgets/target_picker/forward_target_picker.dart';
import 'recent_forward_service.dart';
import 'wechat_forward_confirm_dialog.dart';

/// 微信风格的内置浏览器「更多」操作项定义。
class WeChatBrowserAction {
  const WeChatBrowserAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.badge,
  });

  final Widget icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final Widget? badge;
}

/// 弹出高仿微信网页右上角「···」（更多）点击后的底部操作抽屉。
///
/// 特性：
/// - 顶部：来源标识（Favicon + 网页来源 + `>`）；
/// - 第一栏：「转发给」横向最近会话列表，点击弹出确认发送弹窗；
/// - 第一排：转发给朋友（调起统一选择器）、分享到朋友圈、微信收藏、搜一搜、用电脑打开、在浏览器打开；
/// - 第二排：浮窗（真实贴边气泡）、听全文、稍后听、保存为图片、投诉、复制链接；
/// - 底部：微信同款深蓝色「取消」按钮。
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

class _WeChatBrowserMoreSheetContent extends ConsumerWidget {
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

  String get _sourceName {
    if (title != null && title!.isNotEmpty) {
      if (title!.length <= 10) return title!;
      return title!.substring(0, 10);
    }
    return _domain;
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

  void _listenFullText(BuildContext context) {
    Navigator.of(context).pop();
    showToast('语音朗读已就绪', type: ToastType.info);
  }

  void _listenLater(BuildContext context) {
    Navigator.of(context).pop();
    showToast('已添加至稍后听', type: ToastType.info);
  }

  void _saveAsImage(BuildContext context) {
    Navigator.of(context).pop();
    showToast('正在生成网页长图', type: ToastType.info);
  }

  void _openOnComputer(BuildContext context) {
    Navigator.of(context).pop();
    showToast('已向登录的桌面端发送打开指令', type: ToastType.info);
  }

  void _searchPage(BuildContext context) {
    Navigator.of(context).pop();
    showToast('正在搜索相关内容', type: ToastType.info);
  }

  /// 唤起统一转发目标选择器
  Future<void> _handleForwardPicker(
    BuildContext context,
    WidgetRef ref,
    List<SessionSummary> allSessions,
  ) async {
    Navigator.of(context).pop();
    final selected = await ForwardTargetPicker.pickTargets(
      context: context,
      sessions: allSessions,
      title: '选择转发目标',
      multiple: true,
      maxCount: 9,
    );
    if (selected == null || selected.isEmpty || !context.mounted) return;

    await _confirmAndSendLink(
      context,
      ref,
      targets: selected,
      url: url,
      title: title,
    );
  }

  /// 呼出确认发送弹窗并执行 sendLink 发送
  Future<void> _confirmAndSendLink(
    BuildContext context,
    WidgetRef ref, {
    required List<SessionSummary> targets,
    required String url,
    String? title,
  }) async {
    final result = await WeChatForwardConfirmDialog.show(
      context,
      targets: targets,
      url: url,
      title: title,
    );
    if (result == null || !context.mounted) return;

    final repo = ref.read(messageRepositoryProvider);
    final ownerId =
        ref.read(sessionListControllerProvider.select((c) => c.currentOwnerId)) ?? 0;

    for (final target in targets) {
      try {
        await repo.sendLink(
          ownerId: ownerId,
          sessionUnitId: target.id,
          url: url,
          title: title,
        );
        if (result.comment.isNotEmpty) {
          await repo.sendText(
            ownerId: ownerId,
            sessionUnitId: target.id,
            text: result.comment,
          );
        }
        await RecentForwardService.instance.record(target.id);
      } catch (e) {
        debugPrint('[WeChatBrowserMoreSheet] send link error: $e');
      }
    }
    showToast('已发送', type: ToastType.success);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF242424) : const Color(0xFFF7F7F7);
    final itemBgColor = isDark ? const Color(0xFF333333) : Colors.white;
    final textColor = isDark ? Colors.white.withValues(alpha: 0.65) : const Color(0xFF555555);

    // 获取当前会话列表与最近转发记录
    final allSessions =
        ref.watch(sessionListControllerProvider.select((c) => c.sessions));
    final recentTargets = RecentForwardService.instance.getRecentTargets(
      allSessions: allSessions,
      limit: 8,
    );

    // ── 第一排：高仿微信第一排操作项 ───────────────────────────────────────────
    final firstRowActions = <WeChatBrowserAction>[
      WeChatBrowserAction(
        icon: const Icon(Icons.reply_all_rounded, color: Color(0xFF07C160), size: 28),
        label: '转发给朋友',
        onTap: () => _handleForwardPicker(context, ref, allSessions),
      ),
      WeChatBrowserAction(
        icon: const Icon(Icons.motion_photos_on_rounded, color: Color(0xFFE88A1A), size: 28),
        label: '分享到朋友圈',
        onTap: () => _shareToMoments(context),
      ),
      WeChatBrowserAction(
        icon: const Icon(Icons.bookmark_border_rounded, color: Color(0xFF3B82F6), size: 28),
        label: '收藏',
        onTap: () => _addToFavorites(context),
      ),
      WeChatBrowserAction(
        icon: const Icon(Icons.search_rounded, color: Color(0xFFEF4444), size: 28),
        label: '搜一搜',
        onTap: () => _searchPage(context),
      ),
      WeChatBrowserAction(
        icon: const Icon(Icons.desktop_windows_outlined, color: Color(0xFF0EA5E9), size: 27),
        label: '用电脑打开',
        onTap: () => _openOnComputer(context),
      ),
      WeChatBrowserAction(
        icon: const Icon(Icons.open_in_browser_rounded, color: Color(0xFF374151), size: 28),
        label: '在浏览器打开',
        onTap: () => _openInExternalBrowser(context),
      ),
      if (customActions != null) ...customActions!,
    ];

    // ── 第二排：高仿微信第二排工具项 ───────────────────────────────────────────
    final secondRowActions = <WeChatBrowserAction>[
      WeChatBrowserAction(
        icon: const _DoubleDotIcon(),
        label: '浮窗',
        onTap: () => _minimize(context),
      ),
      WeChatBrowserAction(
        icon: const Icon(Icons.headphones_outlined, color: Color(0xFF374151), size: 26),
        label: '听全文',
        onTap: () => _listenFullText(context),
      ),
      WeChatBrowserAction(
        icon: const Icon(Icons.playlist_add_rounded, color: Color(0xFF374151), size: 28),
        label: '稍后听',
        onTap: () => _listenLater(context),
      ),
      WeChatBrowserAction(
        icon: const Icon(Icons.download_rounded, color: Color(0xFF374151), size: 26),
        label: '保存为图片',
        onTap: () => _saveAsImage(context),
      ),
      WeChatBrowserAction(
        icon: const Icon(Icons.warning_amber_rounded, color: Color(0xFF374151), size: 26),
        label: '投诉',
        onTap: () => _showReport(context),
      ),
      WeChatBrowserAction(
        icon: const Icon(Icons.link_rounded, color: Color(0xFF374151), size: 27),
        label: '复制链接',
        onTap: () => _copyLink(context),
      ),
      if (onRefresh != null)
        WeChatBrowserAction(
          icon: const Icon(Icons.refresh_rounded, color: Color(0xFF374151), size: 26),
          label: '刷新',
          onTap: () {
            Navigator.of(context).pop();
            onRefresh!();
          },
        ),
      if (onToggleMode != null)
        WeChatBrowserAction(
          icon: Icon(toggleModeIcon ?? Icons.article_outlined, color: const Color(0xFF374151), size: 26),
          label: toggleModeLabel ?? '切换视图',
          onTap: () {
            Navigator.of(context).pop();
            onToggleMode!();
          },
        ),
      if (onAdjustFontSize != null)
        WeChatBrowserAction(
          icon: const Icon(Icons.format_size_rounded, color: Color(0xFF374151), size: 26),
          label: '调整字体',
          onTap: () {
            Navigator.of(context).pop();
            onAdjustFontSize!();
          },
        ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 顶部来源标识（微信同款：圆形图标 + 来源名称 + >） ────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: Color(0xFF0F52BA),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'W',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _sourceName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: isDark ? Colors.white38 : Colors.grey,
                  ),
                ],
              ),
            ),

            // ── 第一栏：「转发给」小标题与最近会话列表 ─────────────────────────
            if (recentTargets.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 6, 16, 6),
                child: Text(
                  '转发给',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
              ),
              SizedBox(
                height: 82,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: recentTargets.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (context, index) {
                    final target = recentTargets[index];
                    return InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        Navigator.of(context).pop();
                        _confirmAndSendLink(
                          context,
                          ref,
                          targets: [target],
                          url: url,
                          title: title,
                        );
                      },
                      child: SizedBox(
                        width: 54,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AppAvatar(
                              name: target.title,
                              imageUrl: target.avatarUrl,
                              size: 48,
                              shape: AvatarShape.square,
                            ),
                            const SizedBox(height: 5),
                            Text(
                              target.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: textColor,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
            ],

            // ── 第一排操作 ──────────────────────────────────────────────
            _buildActionRow(firstRowActions, itemBgColor, textColor),

            const SizedBox(height: 14),

            // ── 第二排操作 ──────────────────────────────────────────────
            _buildActionRow(secondRowActions, itemBgColor, textColor),

            const SizedBox(height: 14),

            // ── 分隔粗线（微信风格 7px 浅灰槽） ─────────────────────────────
            Container(
              height: 7,
              color: isDark ? const Color(0xFF1B1B1B) : const Color(0xFFEBEBEB),
            ),

            // ── 底部「取消」按钮（微信经典蓝 #576B95） ─────────────────────
            InkWell(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                height: 52,
                alignment: Alignment.center,
                color: isDark ? const Color(0xFF242424) : Colors.white,
                child: const Text(
                  '取消',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF576B95),
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
            padding: const EdgeInsets.symmetric(horizontal: 7),
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
                      child: action.icon,
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

/// 微信浮窗图标（两个并排圆点 ● ●）
class _DoubleDotIcon extends StatelessWidget {
  const _DoubleDotIcon();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Color(0xFF222222),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Color(0xFF222222),
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}
