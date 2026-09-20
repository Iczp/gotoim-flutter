import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/compliance/agreement_viewer_page.dart';
import '../../../core/compliance/privacy_service.dart';
import '../../../core/theme/font_scale_controller.dart';
import '../../../core/theme/theme_mode_controller.dart';
import '../../../core/widgets/app_modal.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/cell_group.dart';
import '../../app_update/application/app_update_service.dart';
import '../../auth/application/auth_controller.dart';

/// 设置总入口页面
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

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

  Future<void> _clearCache(BuildContext context) async {
    final confirmed = await showConfirmModal(
      context: context,
      title: '清理临时缓存',
      message: '将清理本地图片预览、临时文件与离线快照，不会删除聊天历史记录。',
      confirmText: '立即清理',
    );
    if (confirmed && context.mounted) {
      showToast('临时缓存已成功清理', type: ToastType.success);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final themeMode = ref.watch(themeModeProvider);
    final fontScale = ref.watch(fontScaleProvider);
    final fontLevel = FontScaleLevel.fromScale(fontScale);

    final themeModeLabel = switch (themeMode) {
      ThemeMode.system => '跟随系统',
      ThemeMode.light => '浅色模式',
      ThemeMode.dark => '深色模式',
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // ── 1. 账号与安全 ──────────────────────────────────────────
          CellGroup(
            title: '账号与安全',
            children: [
              Cell(
                icon: const Icon(Icons.person_outline_rounded),
                title: '个人信息',
                subtitle: '头像、昵称、签名与基础设置',
                showArrow: true,
                onTap: () => context.push('/account/profile'),
              ),
              Cell(
                icon: const Icon(Icons.manage_accounts_outlined),
                title: '账号管理',
                subtitle: '切换或管理当前登录身份',
                showArrow: true,
                onTap: () => context.push('/mine/account'),
              ),
              Cell(
                icon: const Icon(Icons.devices_rounded),
                title: '登录设备',
                subtitle: '已登录设备列表与下线管理',
                showArrow: true,
                onTap: () => context.push('/devices'),
              ),
            ],
          ),

          // ── 2. 通用与显示 ──────────────────────────────────────────
          CellGroup(
            title: '通用与显示',
            children: [
              Cell(
                icon: const Icon(Icons.palette_outlined),
                title: '外观与主题',
                subtitle: '深浅模式、字体大小、过界动效与毛玻璃',
                value: '$themeModeLabel · ${fontLevel.label}',
                showArrow: true,
                onTap: () => context.push('/settings/theme'),
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
            ],
          ),

          // ── 3. 系统与支持 ──────────────────────────────────────────
          CellGroup(
            title: '系统与支持',
            children: [
              Cell(
                icon: const Icon(Icons.cleaning_services_outlined),
                title: '清理临时缓存',
                subtitle: '清理本地图片缩略图与临时缓存',
                showArrow: true,
                onTap: () => _clearCache(context),
              ),
              Cell(
                icon: const Icon(Icons.system_update_rounded),
                title: '检查新版本',
                subtitle: '获取最新版本特性与修复更新',
                value: 'v${ref.watch(appUpdateServiceProvider).currentVersionName}',
                showArrow: true,
                onTap: () => ref.read(appUpdateServiceProvider).checkUpdate(
                  silent: false,
                  context: context,
                ),
              ),
              Cell(
                icon: const Icon(Icons.description_outlined),
                title: '用户服务协议',
                showArrow: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AgreementViewerPage(
                      title: PrivacyService.userAgreementTitle,
                      content: PrivacyService.userAgreementContent,
                      url: PrivacyService.userAgreementUrl,
                    ),
                  ),
                ),
              ),
              Cell(
                icon: const Icon(Icons.privacy_tip_outlined),
                title: '隐私保护政策',
                showArrow: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AgreementViewerPage(
                      title: PrivacyService.privacyPolicyTitle,
                      content: PrivacyService.privacyPolicyContent,
                      url: PrivacyService.privacyPolicyUrl,
                    ),
                  ),
                ),
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

          // ── 4. 账号退出 ──────────────────────────────────────────
          CellGroup(
            margin: const EdgeInsets.only(top: 8, bottom: 24),
            children: [
              Cell(
                icon: Icon(Icons.logout_rounded, color: colorScheme.error),
                title: '退出登录',
                titleColor: colorScheme.error,
                isCentered: true,
                onTap: () => _confirmLogout(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
