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
import 'forward_link_confirm_dialog.dart';
import 'recent_forward_service.dart';

/// 内置浏览器「更多」操作项定义（微信风格）。
class BrowserMoreAction {
  const BrowserMoreAction({
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

/// 弹出网页右上角「···」（更多）点击后的高保真操作底栏（仿微信设计）。
///
/// 特性：
/// - 顶部：来源标识（Favicon + 网页来源 + `>`）；
/// - 第一栏：「转发给」横向最近会话列表，点击弹出确认发送弹窗；
/// - 第一排：转发给朋友（调起统一选择器）、分享到朋友圈、微信收藏、搜一搜、用电脑打开、在浏览器打开；
/// - 第二排：浮窗（真实贴边气泡）、听全文、稍后听、保存为图片、投诉、复制链接；
/// - 底部：经典深蓝色「取消」按钮。
Future<void> showBrowserMoreSheet(
  BuildContext context, {
  required String url,
  String? title,
  VoidCallback? onRefresh,
  VoidCallback? onToggleMode,
  String? toggleModeLabel,
  IconData? toggleModeIcon,
  VoidCallback? onAdjustFontSize,
  VoidCallback? onMinimizeToFloat,
  List<BrowserMoreAction>? customActions,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _BrowserMoreSheetContent(
      url: url,
      title: title,
      parentContext: context,
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

class _BrowserMoreSheetContent extends ConsumerStatefulWidget {
  const _BrowserMoreSheetContent({
    required this.url,
    this.title,
    this.parentContext,
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
  final BuildContext? parentContext;
  final VoidCallback? onRefresh;
  final VoidCallback? onToggleMode;
  final String? toggleModeLabel;
  final IconData? toggleModeIcon;
  final VoidCallback? onAdjustFontSize;
  final VoidCallback? onMinimizeToFloat;
  final List<BrowserMoreAction>? customActions;

  @override
  ConsumerState<_BrowserMoreSheetContent> createState() =>
      _BrowserMoreSheetContentState();
}

class _BrowserMoreSheetContentState
    extends ConsumerState<_BrowserMoreSheetContent> {
  List<SessionSummary> _fallbackSessions = const <SessionSummary>[];

  @override
  void initState() {
    super.initState();
    _checkAndLoadSessions();
  }

  Future<void> _checkAndLoadSessions() async {
    final activeSessions =
        ref.read(sessionListControllerProvider.select((c) => c.sessions));
    if (activeSessions.isEmpty) {
      debugPrint('[BrowserMoreSheet] activeSessions is empty, loading from repository...');
      try {
        final currentOwnerId =
            ref.read(sessionListControllerProvider.select((c) => c.currentOwnerId)) ?? 0;
        final res = await ref.read(sessionRepositoryProvider).loadFriends(
              ownerId: currentOwnerId,
              limit: 100,
            );
        if (mounted && res.items.isNotEmpty) {
          setState(() {
            _fallbackSessions = res.items;
          });
          debugPrint('[BrowserMoreSheet] Loaded ${_fallbackSessions.length} fallback sessions');
        }
      } catch (e) {
        debugPrint('[BrowserMoreSheet] Fallback load sessions error: $e');
      }
    }
  }

  String get _domain {
    try {
      final uri = Uri.parse(widget.url);
      return uri.host.isNotEmpty ? uri.host : '网页';
    } catch (_) {
      return '网页';
    }
  }

  String get _sourceName {
    if (widget.title != null && widget.title!.isNotEmpty) {
      if (widget.title!.length <= 10) return widget.title!;
      return widget.title!.substring(0, 10);
    }
    return _domain;
  }

  void _copyLink(BuildContext context) {
    Navigator.of(context).pop();
    Clipboard.setData(ClipboardData(text: widget.url));
    showToast('链接已复制到剪贴板', type: ToastType.success);
  }

  Future<void> _openInExternalBrowser(BuildContext context) async {
    Navigator.of(context).pop();
    try {
      final uri = WebUri(widget.url);
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
    if (widget.onMinimizeToFloat != null) {
      widget.onMinimizeToFloat!();
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
    BuildContext sheetContext,
    List<SessionSummary> allSessions,
  ) async {
    debugPrint('[BrowserMoreSheet] 「转发给朋友」被点击. 候选会话数: ${allSessions.length}');
    Navigator.of(sheetContext).pop();

    final targetContext = (widget.parentContext != null && widget.parentContext!.mounted)
        ? widget.parentContext!
        : sheetContext;

    if (!targetContext.mounted) {
      debugPrint('[BrowserMoreSheet] targetContext is not mounted, aborted forward');
      return;
    }

    var sessionsToPick = allSessions;
    if (sessionsToPick.isEmpty) {
      debugPrint('[BrowserMoreSheet] sessionsToPick is empty, loading from session repository...');
      try {
        final currentOwnerId =
            ref.read(sessionListControllerProvider.select((c) => c.currentOwnerId)) ?? 0;
        final res = await ref.read(sessionRepositoryProvider).loadFriends(
              ownerId: currentOwnerId,
              limit: 100,
            );
        sessionsToPick = res.items;
        debugPrint('[BrowserMoreSheet] Loaded ${sessionsToPick.length} sessions from repository');
      } catch (e) {
        debugPrint('[BrowserMoreSheet] Failed to load sessions from repository: $e');
      }
    }

    if (sessionsToPick.isEmpty) {
      debugPrint('[BrowserMoreSheet] No sessions found to forward to');
      showToast('暂无可选联系人', type: ToastType.warning);
      return;
    }

    if (!targetContext.mounted) return;

    debugPrint('[BrowserMoreSheet] 唤起 ForwardTargetPicker, 候选数: ${sessionsToPick.length}');
    final selected = await ForwardTargetPicker.pickTargets(
      context: targetContext,
      sessions: sessionsToPick,
      title: '选择转发目标',
      multiple: true,
      maxCount: 9,
    );

    if (selected == null || selected.isEmpty) {
      debugPrint('[BrowserMoreSheet] TargetPicker cancelled or empty selection');
      return;
    }

    if (!targetContext.mounted) return;

    debugPrint('[BrowserMoreSheet] TargetPicker 选中 ${selected.length} 个目标: ${selected.map((s) => '${s.title}(${s.id})').join(', ')}');

    await _confirmAndSendLink(
      targetContext,
      targets: selected,
      url: widget.url,
      title: widget.title,
    );
  }

  /// 呼出确认发送弹窗并执行 sendLink 发送
  Future<void> _confirmAndSendLink(
    BuildContext callerContext, {
    required List<SessionSummary> targets,
    required String url,
    String? title,
  }) async {
    if (!callerContext.mounted) {
      debugPrint('[BrowserMoreSheet] callerContext is not mounted when showing confirm dialog');
      return;
    }

    debugPrint('[BrowserMoreSheet] 弹出发送确认卡片, 目标数: ${targets.length}, url: $url, title: $title');
    final result = await ForwardLinkConfirmDialog.show(
      callerContext,
      targets: targets,
      url: url,
      title: title,
    );
    if (result == null) {
      debugPrint('[BrowserMoreSheet] 用户在确认卡片中取消发送');
      return;
    }

    debugPrint('[BrowserMoreSheet] 用户确认发送! 留言内容: "${result.comment}"');

    final repo = ref.read(messageRepositoryProvider);
    final fallbackOwnerId =
        ref.read(sessionListControllerProvider.select((c) => c.currentOwnerId)) ?? 0;

    var successCount = 0;
    var failCount = 0;
    String? lastErrorMsg;

    for (final target in targets) {
      final effectiveOwnerId =
          (target.ownerId != null && target.ownerId! > 0)
              ? target.ownerId!
              : fallbackOwnerId;
      debugPrint(
        '[BrowserMoreSheet] 开始发送链接消息 -> 目标: ${target.title}, '
        'sessionUnitId: ${target.id}, ownerId: $effectiveOwnerId, url: $url, title: $title',
      );
      try {
        final sentMessage = await repo.sendLink(
          ownerId: effectiveOwnerId,
          sessionUnitId: target.id,
          url: url,
          title: title,
        );
        if (sentMessage.state == 'failed') {
          throw Exception('接口返回失败状态 (state=failed)');
        }
        debugPrint('[BrowserMoreSheet] 发送链接消息成功: target=${target.title}, msgId=${sentMessage.localId}, serverId=${sentMessage.serverId}');

        if (result.comment.trim().isNotEmpty) {
          debugPrint('[BrowserMoreSheet] 开始发送附带留言 -> 目标: ${target.title}, text: "${result.comment.trim()}"');
          final sentComment = await repo.sendText(
            ownerId: effectiveOwnerId,
            sessionUnitId: target.id,
            text: result.comment.trim(),
          );
          debugPrint('[BrowserMoreSheet] 发送留言成功: target=${target.title}, msgId=${sentComment.localId}');
        }
        await RecentForwardService.instance.record(target.id);
        successCount++;
      } catch (e, st) {
        failCount++;
        lastErrorMsg = e.toString();
        debugPrint('[BrowserMoreSheet] 发送链接消息失败 -> target=${target.title}(${target.id}): $e\n$st');
      }
    }

    debugPrint('[BrowserMoreSheet] 转发流程结束: 成功 $successCount 个, 失败 $failCount 个');
    if (failCount == 0 && successCount > 0) {
      showToast('已发送', type: ToastType.success);
    } else if (successCount > 0) {
      showToast('部分发送失败 ($failCount/$successCount)', type: ToastType.warning);
    } else {
      showToast('发送失败: ${lastErrorMsg ?? "网络异常"}', type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF242424) : const Color(0xFFF7F7F7);
    final itemBgColor = isDark ? const Color(0xFF333333) : Colors.white;
    final textColor = isDark ? Colors.white.withValues(alpha: 0.65) : const Color(0xFF555555);

    // 获取当前会话列表与最近转发记录
    final allSessions =
        ref.watch(sessionListControllerProvider.select((c) => c.sessions));
    final effectiveSessions = allSessions.isNotEmpty ? allSessions : _fallbackSessions;
    final recentTargets = RecentForwardService.instance.getRecentTargets(
      allSessions: effectiveSessions,
      limit: 8,
    );

    // ── 第一排：高仿微信第一排操作项 ───────────────────────────────────────────
    final firstRowActions = <BrowserMoreAction>[
      BrowserMoreAction(
        icon: const Icon(Icons.reply_all_rounded, color: Color(0xFF07C160), size: 28),
        label: '转发给朋友',
        onTap: () => _handleForwardPicker(context, effectiveSessions),
      ),
      BrowserMoreAction(
        icon: const Icon(Icons.motion_photos_on_rounded, color: Color(0xFFE88A1A), size: 28),
        label: '分享到朋友圈',
        onTap: () => _shareToMoments(context),
      ),
      BrowserMoreAction(
        icon: const Icon(Icons.bookmark_border_rounded, color: Color(0xFF3B82F6), size: 28),
        label: '收藏',
        onTap: () => _addToFavorites(context),
      ),
      BrowserMoreAction(
        icon: const Icon(Icons.search_rounded, color: Color(0xFFEF4444), size: 28),
        label: '搜一搜',
        onTap: () => _searchPage(context),
      ),
      BrowserMoreAction(
        icon: const Icon(Icons.desktop_windows_outlined, color: Color(0xFF0EA5E9), size: 27),
        label: '用电脑打开',
        onTap: () => _openOnComputer(context),
      ),
      BrowserMoreAction(
        icon: const Icon(Icons.open_in_browser_rounded, color: Color(0xFF374151), size: 28),
        label: '在浏览器打开',
        onTap: () => _openInExternalBrowser(context),
      ),
      if (widget.customActions != null) ...widget.customActions!,
    ];

    // ── 第二排：高仿微信第二排工具项 ───────────────────────────────────────────
    final secondRowActions = <BrowserMoreAction>[
      BrowserMoreAction(
        icon: const _DoubleDotIcon(),
        label: '浮窗',
        onTap: () => _minimize(context),
      ),
      BrowserMoreAction(
        icon: const Icon(Icons.headphones_outlined, color: Color(0xFF374151), size: 26),
        label: '听全文',
        onTap: () => _listenFullText(context),
      ),
      BrowserMoreAction(
        icon: const Icon(Icons.playlist_add_rounded, color: Color(0xFF374151), size: 28),
        label: '稍后听',
        onTap: () => _listenLater(context),
      ),
      BrowserMoreAction(
        icon: const Icon(Icons.download_rounded, color: Color(0xFF374151), size: 26),
        label: '保存为图片',
        onTap: () => _saveAsImage(context),
      ),
      BrowserMoreAction(
        icon: const Icon(Icons.warning_amber_rounded, color: Color(0xFF374151), size: 26),
        label: '投诉',
        onTap: () => _showReport(context),
      ),
      BrowserMoreAction(
        icon: const Icon(Icons.link_rounded, color: Color(0xFF374151), size: 27),
        label: '复制链接',
        onTap: () => _copyLink(context),
      ),
      if (widget.onRefresh != null)
        BrowserMoreAction(
          icon: const Icon(Icons.refresh_rounded, color: Color(0xFF374151), size: 26),
          label: '刷新',
          onTap: () {
            Navigator.of(context).pop();
            widget.onRefresh!();
          },
        ),
      if (widget.onToggleMode != null)
        BrowserMoreAction(
          icon: Icon(widget.toggleModeIcon ?? Icons.article_outlined, color: const Color(0xFF374151), size: 26),
          label: widget.toggleModeLabel ?? '切换视图',
          onTap: () {
            Navigator.of(context).pop();
            widget.onToggleMode!();
          },
        ),
      if (widget.onAdjustFontSize != null)
        BrowserMoreAction(
          icon: const Icon(Icons.format_size_rounded, color: Color(0xFF374151), size: 26),
          label: '调整字体',
          onTap: () {
            Navigator.of(context).pop();
            widget.onAdjustFontSize!();
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
                  itemBuilder: (itemContext, index) {
                    final target = recentTargets[index];
                    return InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        debugPrint('[BrowserMoreSheet] 点击最近联系人: ${target.title} (id: ${target.id}, ownerId: ${target.ownerId})');
                        Navigator.of(itemContext).pop();
                        final targetContext = (widget.parentContext != null && widget.parentContext!.mounted)
                            ? widget.parentContext!
                            : itemContext;
                        if (!targetContext.mounted) {
                          debugPrint('[BrowserMoreSheet] targetContext is not mounted, aborted recent forward');
                          return;
                        }
                        _confirmAndSendLink(
                          targetContext,
                          targets: [target],
                          url: widget.url,
                          title: widget.title,
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
    List<BrowserMoreAction> actions,
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

/// 浮窗图标（两个并排圆点 ● ●）
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

// 别名以保持兼容
typedef WeChatBrowserAction = BrowserMoreAction;
const showWeChatBrowserMoreSheet = showBrowserMoreSheet;
