import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/scan/unified_scan_dispatcher.dart';
import '../../../core/theme/tab_glass_controller.dart';
import '../../../core/theme/theme_mode_controller.dart';
import '../../../core/theme/overscroll_style_controller.dart';
import '../../../core/widgets/app_modal.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/cell_group.dart';
import '../../../core/widgets/glass_container.dart';
import '../../auth/application/auth_controller.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../session/application/session_list_controller.dart';

/// 「我的」页面（独立组件，由 HomeSectionPage 调用）。
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
    final themeMode = ref.watch(themeModeProvider);
    final overscrollStyle = ref.watch(overscrollStyleProvider);
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
                              alpha: 0.6,
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
                          color: colorScheme.onSurfaceVariant,
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

        // ── 外观与主题 ──────────────────────────────────────────────
        CellGroup(
          title: '外观与主题',
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    themeMode == ThemeMode.dark
                        ? Icons.dark_mode_rounded
                        : themeMode == ThemeMode.light
                        ? Icons.light_mode_rounded
                        : Icons.brightness_auto_rounded,
                    size: 20,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '主题模式',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.system,
                    icon: Icon(Icons.brightness_auto_outlined),
                    label: Text('跟随系统'),
                  ),
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode_outlined),
                    label: Text('浅色模式'),
                  ),
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode_outlined),
                    label: Text('深色模式'),
                  ),
                ],
                selected: {themeMode},
                onSelectionChanged: (selected) {
                  if (selected.isNotEmpty) {
                    ref
                        .read(themeModeControllerProvider.notifier)
                        .setThemeMode(selected.first);
                  }
                },
              ),
              const SizedBox(height: 18),
              Text(
                '列表过界效果',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '可选择 iOS 式回弹或 Android 式拉伸效果。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),

              SegmentedButton<OverscrollStyle>(
                segments: OverscrollStyle.values
                    .map(
                      (style) => ButtonSegment<OverscrollStyle>(
                        value: style,
                        label: Text(style.label),
                      ),
                    )
                    .toList(growable: false),
                selected: {overscrollStyle},
                onSelectionChanged: (selected) {
                  if (selected.isNotEmpty) {
                    ref
                        .read(overscrollStyleControllerProvider.notifier)
                        .setStyle(selected.first);
                  }
                },
              ),
              const SizedBox(height: 12),
              const Divider(height: 0.25),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.blur_on_rounded),
                title: const Text('底部导航毛玻璃效果'),
                subtitle: const Text('开启后导航栏具有高斯模糊与半透明质感'),
                value: ref.watch(tabGlassProvider),
                onChanged: (val) {
                  ref.read(tabGlassProvider.notifier).setEnabled(val);
                },
              ),
            ],
          ),
        ),

        // ── 设置 ──────────────────────────────────────────────────
        CellGroup(
          title: '设置',
          children: [
            Cell(
              icon: const Icon(Icons.manage_accounts_outlined),
              title: '账号管理',
              showArrow: true,
              onTap: () => context.push('/mine/account'),
            ),
            Cell(
              icon: const Icon(Icons.devices_rounded),
              title: '设备信息',
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
                subtitle: '全套架构、Realtime、Native 及主题诊断',
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
              showArrow: true,
              onTap: () => _confirmLogout(context, ref),
            ),
          ],
        ),
      ],
    );
  }
}
