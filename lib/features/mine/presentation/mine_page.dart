import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/device/client_device_context.dart';
import '../../../core/services/scan/unified_scan_dispatcher.dart';
import '../../../core/services/window_service.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/cell_group.dart';
import '../../../core/widgets/desktop_dialog.dart';
import '../../../core/widgets/glass_container.dart';
import '../../account/presentation/account_profile_page.dart';
import '../../app_update/application/app_update_service.dart';
import '../../home/presentation/home_sections.dart';
import '../../session/application/session_list_controller.dart';
import '../../session/presentation/login_devices_page.dart';
import '../../settings/presentation/theme_settings_page.dart';
import '../../social/application/social_notifications_controller.dart';
import 'my_qr_code_dialog.dart';

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
    final appUpdateService = ref.watch(appUpdateServiceProvider);
    final deviceContext = ref.watch(clientDeviceContextProvider);
    final socialUnread = ref.watch(socialNotificationsProvider.select((state) => state.unreadCount));
    final headerOffset = TabHeaderHeightScope.of(context);
    final topPadding = headerOffset > 0 ? headerOffset + 8.0 : 16.0;

    final isDesktop = (!kIsWeb &&
            (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) ||
        MediaQuery.sizeOf(context).width >= 720;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        isCompact ? 16 : 32,
        topPadding,
        isCompact ? 16 : 32,
        16 + getHomeBottomPadding(context, isCompact: isCompact),
      ),
      children: [
        // ── 用户信息卡 ──────────────────────────────────────────────
        GlassCard(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
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
                  onTap: () {
                    if (isDesktop) {
                      showDesktopModalDialog<void>(
                        context: context,
                        title: '账号与个人信息',
                        width: 500,
                        height: 600,
                        child: const AccountProfilePage(),
                      );
                    } else {
                      context.push('/account/profile');
                    }
                  },
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
                tooltip: '我的二维码名片',
                icon: const Icon(Icons.qr_code_2_rounded, size: 26),
                onPressed: () {
                  if (isDesktop) {
                    MyQrCodeDialog.show(context, owner: currentOwner);
                  } else {
                    context.push('/mine/qr-code');
                  }
                },
              ),
            ],
          ),
        ),

        // ── 核心功能与协同工具 ──────────────────────────────────────
        CellGroup(
          title: '常用服务',
          children: [
            Cell(
              icon: const Icon(Icons.dynamic_feed_outlined),
              title: 'Social 社交',
              valueWidget: socialUnread > 0 ? Badge(label: Text(socialUnread > 99 ? '99+' : '$socialUnread')) : null,
              subtitle: '查看推荐与关注动态',
              showArrow: true,
              onTap: () => context.push('/social'),
            ),
            Cell(
              icon: const Icon(Icons.qr_code_scanner_rounded),
              title: '扫一扫',
              subtitle: '扫码登录、加好友、加群或识别二维码',
              showArrow: true,
              onTap: () {
                ref
                    .read(unifiedScanDispatcherProvider)
                    .openAndDispatch(context, ref);
              },
            ),
            Cell(
              icon: const Icon(Icons.qr_code_rounded),
              title: '我的二维码名片',
              subtitle: '展示个人专属二维码，面对面扫码加好友',
              showArrow: true,
              onTap: () {
                if (isDesktop) {
                  MyQrCodeDialog.show(context, owner: currentOwner);
                } else {
                  context.push('/mine/qr-code');
                }
              },
            ),
            Cell(
              icon: const Icon(Icons.devices_other_rounded),
              title: '登录设备管理',
              subtitle: '查看当前在线终端及历史登录设备',
              value: sessionController.onlineDevices.isNotEmpty
                  ? '${sessionController.onlineDevices.length} 台在线'
                  : null,
              showArrow: true,
              onTap: () {
                if (isDesktop) {
                  showDesktopModalDialog<void>(
                    context: context,
                    title: '多端登录设备管理',
                    width: 480,
                    height: 620,
                    child: const LoginDevicesPage(),
                  );
                } else {
                  context.push('/devices');
                }
              },
            ),
            Cell(
              icon: const Icon(Icons.folder_shared_outlined),
              title: '局域网快传 / 文件共享',
              subtitle: '同 Wi-Fi 局域网大文件极速互传与本地文件服务',
              showArrow: true,
              onTap: () {
                if (isDesktop) {
                  ref.read(windowServiceProvider).openLocalFileServer();
                } else {
                  context.push('/local-file-server');
                }
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
          ],
        ),

        const SizedBox(height: 12),

        // ── 偏好与系统设置 ──────────────────────────────────────────
        CellGroup(
          title: '设置与关于',
          children: [
            Cell(
              icon: const Icon(Icons.settings_outlined),
              title: '通用设置',
              subtitle: '账号管理、外观主题与系统选项',
              showArrow: true,
              onTap: () {
                if (isDesktop) {
                  ref.read(windowServiceProvider).openSettings();
                } else {
                  context.push('/settings');
                }
              },
            ),
            Cell(
              icon: const Icon(Icons.palette_outlined),
              title: '外观与主题',
              subtitle: '深色模式、强调色及玻璃拟物特效',
              showArrow: true,
              onTap: () {
                if (isDesktop) {
                  showDesktopModalDialog<void>(
                    context: context,
                    title: '外观与主题设置',
                    width: 440,
                    height: 480,
                    child: const ThemeSettingsPage(),
                  );
                } else {
                  context.push('/settings/theme');
                }
              },
            ),
            Cell(
              icon: const Icon(Icons.system_update_alt_rounded),
              title: '检查新版本',
              value: 'v${deviceContext.appVersion}',
              showArrow: true,
              onTap: () => appUpdateService.checkUpdate(context: context),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // ── 实验室与开发工具 ────────────────────────────────────────
        CellGroup(
          title: '实验室',
          children: [
            Cell(
              icon: const Icon(Icons.monitor_heart_outlined),
              title: '开发诊断中心',
              subtitle: '网络连通性、SignalR 长连接、本地数据库及原生能力',
              showArrow: true,
              onTap: () {
                if (isDesktop) {
                  ref.read(windowServiceProvider).openDiagnostics();
                } else {
                  context.push('/diagnostics');
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}
