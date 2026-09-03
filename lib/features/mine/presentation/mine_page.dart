import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/scan/unified_scan_dispatcher.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_modal.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/cell_group.dart';
import '../../../core/widgets/glass_container.dart';
import '../../auth/application/auth_controller.dart';
import '../../session/application/session_list_controller.dart';

/// 「我的」页面（由 HomeSectionPage 调用）。
class MinePage extends ConsumerWidget {
  const MinePage({
    required this.isCompact,
    required this.onOpenOwnerDrawer,
    super.key,
  });

  final bool isCompact;
  final VoidCallback onOpenOwnerDrawer;

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmModal(
      context: context,
      title: '退出登录',
      message: '确定要退出当前账号登录吗？\n退出后 Token 将立即在服务器失效。',
      confirmText: '退出',
      isDestructive: true,
    );
    if (confirmed && context.mounted) {
      await ref.read(authControllerProvider).logout();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final sessionController = ref.watch(sessionListControllerProvider);
    final currentOwner = sessionController.currentOwner;

    return ListView(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 16 : 32,
        vertical: 16,
      ),
      children: [
        // ── 用户信息卡 ──────────────────────────────────────────────
        GlassCard(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              InkResponse(
                onTap: onOpenOwnerDrawer,
                radius: 34,
                child: AppAvatar(
                  name: currentOwner?.name ?? 'Goto User',
                  imageUrl: currentOwner?.imageUrl,
                  radius: 30,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: InkWell(
                  onTap: () => context.push('/account/profile'),
                  borderRadius: BorderRadius.circular(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              currentOwner?.name ?? '当前用户',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.chevron_right,
                            size: 20,
                            color: colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        currentOwner?.typeDescription.isNotEmpty == true
                            ? currentOwner!.typeDescription
                            : 'IM 客户端登录用户',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: '凭据与认证诊断',
                icon: const Icon(Icons.qr_code_2_rounded),
                onPressed: () => context.push('/diagnostics/auth'),
              ),
            ],
          ),
        ),

        // ── 我的内容 ──────────────────────────────────────────────
        CellGroup(
          title: '我的内容',
          children: [
            Cell(
              icon: const Icon(Icons.manage_accounts_outlined),
              title: '账号设置',
              showArrow: true,
              onTap: () => context.push('/account/profile'),
            ),
            Cell(
              icon: const Icon(Icons.qr_code_scanner_rounded),
              title: '扫一扫',
              showArrow: true,
              onTap: () {
                ref
                    .read(unifiedScanDispatcherProvider)
                    .openAndDispatch(context, ref);
              },
            ),
            Cell(
              icon: const Icon(Icons.bookmark_outline_rounded),
              title: '我收藏的',
              showArrow: true,
              onTap: () {
                showToast('收藏夹暂无内容', type: ToastType.info);
              },
            ),
            Cell(
              icon: const Icon(Icons.favorite_outline_rounded),
              title: '我关注的',
              showArrow: true,
              onTap: () {
                showToast('关注列表暂无内容', type: ToastType.info);
              },
            ),
          ],
        ),

        // ── 设置与系统服务 ──────────────────────────────────────────
        CellGroup(
          title: '设置与服务',
          children: [
            Cell(
              icon: const Icon(Icons.settings_outlined),
              title: '设置',
              subtitle: '外观主题、字体大小、账号与通用设置',
              showArrow: true,
              onTap: () => context.push('/settings'),
            ),
            Cell(
              icon: const Icon(Icons.devices_rounded),
              title: '登录设备',
              subtitle: '已登录 ${sessionController.devices.length} 台设备',
              showArrow: true,
              onTap: () => context.push('/devices'),
            ),
            Cell(
              icon: const Icon(Icons.folder_shared_outlined),
              title: '局域网文件管理',
              subtitle: 'HTTP 文件收发与 Web 终端',
              showArrow: true,
              onTap: () => context.push('/local-file-server'),
            ),
            Cell(
              icon: const Icon(Icons.qr_code_scanner_rounded),
              title: '扫码登录终端',
              subtitle: '识别二维码并授权登录',
              showArrow: true,
              onTap: () => context.push('/scan-login/scan'),
            ),
            if (kDebugMode)
              Cell(
                icon: const Icon(Icons.developer_mode_rounded),
                title: '开发诊断中心',
                subtitle: '全套架构、Realtime、Native 及诊断',
                showArrow: true,
                onTap: () => context.push('/diagnostics'),
              ),
          ],
        ),

        // ── 账号操作 ──────────────────────────────────────────────
        CellGroup(
          title: '账号操作',
          margin: const EdgeInsets.only(bottom: 24),
          children: [
            Cell(
              icon: Icon(Icons.logout_rounded, color: colorScheme.error),
              title: '退出登录',
              titleColor: colorScheme.error,
              isCentered: true,
              showArrow: true,
              onTap: () => _confirmLogout(context, ref),
            ),
          ],
        ),
      ],
    );
  }
}
