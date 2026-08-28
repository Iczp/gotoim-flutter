import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/theme_mode_controller.dart';
import '../../../core/theme/overscroll_style_controller.dart';
import '../../../core/widgets/glass_container.dart';
import '../../auth/application/auth_controller.dart';
import '../../session/application/session_list_controller.dart';
import '../../session/presentation/chat_object_avatar.dart';
import '../../session/presentation/session_list_page.dart';
import '../../explore/presentation/explore_page.dart';
import '../../contact/presentation/contacts_page.dart';
import '../../workbench/presentation/workbench_page.dart';

/// Top-level section page router for the IM home shell.
class HomeSectionPage extends StatelessWidget {
  const HomeSectionPage({
    required this.section,
    required this.isCompact,
    required this.onOpenOwnerDrawer,
    super.key,
  });

  final HomeSection section;
  final bool isCompact;
  final VoidCallback onOpenOwnerDrawer;

  @override
  Widget build(BuildContext context) {
    if (section == HomeSection.messages) {
      return SessionListPage(onOpenOwnerDrawer: onOpenOwnerDrawer);
    }
    if (section == HomeSection.contacts) {
      return const ContactsPage();
    }
    if (section == HomeSection.workbench) {
      // 工作台内容直接作为 Tab 页面渲染，不再经过“打开工作台”的中转页。
      return const WorkbenchPage();
    }
    if (section == HomeSection.explore) {
      return _HomeSectionWithTitle(
        title: section.label,
        child: ExplorePage(isCompact: isCompact),
      );
    }
    return _HomeSectionWithTitle(
      title: section.label,
      child: _ProfileSettingsPage(
        isCompact: isCompact,
        onOpenOwnerDrawer: onOpenOwnerDrawer,
      ),
    );
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

Color _homeSectionHeaderBackground(BuildContext context) =>
    Theme.of(context).colorScheme.surfaceContainerHighest;

/// A title owned by an individual tab page, rather than by the home shell.
class _HomeSectionWithTitle extends StatelessWidget {
  const _HomeSectionWithTitle({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Material(
            color: _homeSectionHeaderBackground(context),
            child: SizedBox(
              height: kToolbarHeight,
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _ProfileSettingsPage extends ConsumerWidget {
  const _ProfileSettingsPage({
    required this.isCompact,
    required this.onOpenOwnerDrawer,
  });

  final bool isCompact;
  final VoidCallback onOpenOwnerDrawer;

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
        // User Account Card
        GlassCard(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              InkResponse(
                onTap: onOpenOwnerDrawer,
                radius: 34,
                child: ChatObjectAvatar(
                  name: currentOwner?.name ?? 'Goto User',
                  imageUrl: currentOwner?.imageUrl,
                  radius: 30,
                ),
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
              const SizedBox(height: 10),
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
