import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/scan/unified_scan_dispatcher.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/cell_group.dart';
import '../../../core/widgets/glass_container.dart';
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
              icon: const Icon(Icons.settings_outlined),
              title: '设置',
              subtitle: '账号设置、外观与主题、登录设备',
              showArrow: true,
              onTap: () => context.push('/settings'),
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
      ],
    );
  }
}
