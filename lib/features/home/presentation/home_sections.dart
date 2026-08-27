import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/theme_mode_controller.dart';
import '../../../core/widgets/glass_container.dart';
import '../../auth/application/auth_controller.dart';
import '../../session/application/session_list_controller.dart';
import '../../session/presentation/chat_object_avatar.dart';
import '../../session/presentation/session_list_page.dart';
import '../../explore/presentation/explore_page.dart';

/// Top-level section page router for the IM home shell.
class HomeSectionPage extends StatelessWidget {
  const HomeSectionPage({
    required this.section,
    required this.isCompact,
    super.key,
  });

  final HomeSection section;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    if (section == HomeSection.messages) {
      return const SessionListPage();
    }
    if (section == HomeSection.contacts) {
      return _EmptyFeatureState(
        icon: Icons.contacts_outlined,
        title: '通讯录',
        description: '好友、群组及其索引将在联系人数据同步完成后接入。',
        actionLabel: '查看 API 连接',
        onAction: () => context.push('/diagnostics/api'),
        isCompact: isCompact,
      );
    }
    if (section == HomeSection.workbench) {
      return _WorkbenchEntry(isCompact: isCompact);
    }
    if (section == HomeSection.explore) {
      return ExplorePage(isCompact: isCompact);
    }
    return _ProfileSettingsPage(isCompact: isCompact);
  }
}

enum HomeSection { messages, contacts, workbench, explore, profile }

extension HomeSectionInfo on HomeSection {
  String get label {
    if (this == HomeSection.messages) return '消息';
    if (this == HomeSection.contacts) return '通讯录';
    if (this == HomeSection.workbench) return '工作台';
    if (this == HomeSection.explore) return '探索';
    return '我的';
  }

  IconData get icon {
    if (this == HomeSection.messages) return Icons.forum_outlined;
    if (this == HomeSection.contacts) return Icons.contacts_outlined;
    if (this == HomeSection.workbench) return Icons.grid_view_rounded;
    if (this == HomeSection.explore) return Icons.explore_outlined;
    return Icons.person_outline_rounded;
  }

  IconData get selectedIcon {
    if (this == HomeSection.messages) return Icons.forum_rounded;
    if (this == HomeSection.contacts) return Icons.contacts_rounded;
    if (this == HomeSection.workbench) return Icons.grid_view;
    if (this == HomeSection.explore) return Icons.explore_rounded;
    return Icons.person_rounded;
  }
}

class _EmptyFeatureState extends StatelessWidget {
  const _EmptyFeatureState({
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onAction,
    required this.isCompact,
  });

  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback onAction;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isCompact ? 360 : 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 44, color: colorScheme.primary),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                description,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: Text(actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkbenchEntry extends StatelessWidget {
  const _WorkbenchEntry({required this.isCompact});

  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return _EmptyFeatureState(
      icon: Icons.apps_outlined,
      title: '工作台',
      description: '已接入的应用可在工作台中加载，并支持 Deep Link 唤醒。',
      actionLabel: '打开工作台',
      onAction: () => context.push('/workbench'),
      isCompact: isCompact,
    );
  }
}

class _ProfileSettingsPage extends ConsumerWidget {
  const _ProfileSettingsPage({required this.isCompact});

  final bool isCompact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final themeMode = ref.watch(themeModeProvider);
    final sessionController = ref.watch(sessionListControllerProvider);
    final currentOwner = sessionController.currentOwner;

    return ListView(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 16 : 32,
        vertical: 16,
      ),
      children: [
        // User Account Card
        GlassCard(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              ChatObjectAvatar(
                name: currentOwner?.name ?? 'Goto User',
                imageUrl: currentOwner?.imageUrl,
                radius: 30,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentOwner?.name ?? '当前用户',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
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
              IconButton(
                tooltip: '凭据与认证诊断',
                icon: const Icon(Icons.qr_code_2_rounded),
                onPressed: () => context.push('/diagnostics/auth'),
              ),
            ],
          ),
        ),

        // Appearance & Theme Settings Group
        _SectionHeader(title: '外观与主题'),
        GlassCard(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
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
            ],
          ),
        ),

        // System & Feature Navigation Group
        _SectionHeader(title: '常用功能与能力'),
        GlassCard(
          margin: const EdgeInsets.only(bottom: 16),
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.folder_shared_outlined),
                title: const Text('局域网文件管理'),
                subtitle: const Text('HTTP 文件收发与 Web 终端'),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => context.push('/local-file-server'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.devices_rounded),
                title: const Text('登录设备管理'),
                subtitle: Text('已登录 ${sessionController.devices.length} 台设备'),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => context.push('/devices'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.qr_code_scanner_rounded),
                title: const Text('扫码登录终端'),
                subtitle: const Text('识别二维码并授权登录'),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => context.push('/scan-login/scan'),
              ),
              if (kDebugMode) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.developer_mode_rounded),
                  title: const Text('开发诊断中心'),
                  subtitle: const Text('全套架构、Realtime、Native 及主题诊断'),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => context.push('/diagnostics'),
                ),
              ],
            ],
          ),
        ),

        // Account Action
        _SectionHeader(title: '账号操作'),
        GlassCard(
          margin: const EdgeInsets.only(bottom: 24),
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: Icon(Icons.logout_rounded, color: colorScheme.error),
            title: Text(
              '退出登录',
              style: TextStyle(
                color: colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () => ref.read(authControllerProvider).logout(),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
