import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/window_service.dart';
import '../../core/theme/theme_mode_controller.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/app_badge.dart';
import '../../features/home/presentation/home_sections.dart';
import '../../features/session/application/session_list_controller.dart';
import '../../features/session/presentation/desktop_chat_owner_popover.dart';
import '../../features/session/presentation/login_devices_page.dart';

/// 桌面端左侧微信 4.0 风格导航 Dock Rail (DesktopDockRail)
///
/// 核心特性：
/// 1. 最顶部放置当前激活的「聊天身份（ChatOwner）」头像；
/// 2. 头像集成「跨身份未读总数感知红点」，当其他身份收到消息时即刻提示；
/// 3. 单击头像向右唤出轻量级「多身份切换浮窗 (DesktopChatOwnerPopover)」；
/// 4. 纵向排列消息、通讯录、工作台、局域网快传、探索等功能入口，带选中态与未读角标；
/// 5. 底部提供「在线设备协同」、「主题切换」与「全局设置」快捷入口。
class DesktopDockRail extends ConsumerWidget {
  const DesktopDockRail({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final HomeSection selected;
  final ValueChanged<HomeSection> onSelected;

  static const double railWidth = 64.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;
    final sessionController = ref.watch(sessionListControllerProvider);
    final currentOwner = sessionController.currentOwner;
    final otherUnread = sessionController.otherUnreadCount;
    final otherImmersed = sessionController.otherImmersedCount;
    final totalUnread = sessionController.totalUnreadCount;
    final themeMode = ref.watch(themeModeProvider);

    // 微信桌面端经典色：深灰黑背景 #1E1E1E，浅色模式为 #ECECEC
    final railBg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFECECEC);
    final borderColor =
        isDark ? const Color(0x1FFFFFFF) : const Color(0x1F000000);

    return Container(
      width: railWidth,
      decoration: BoxDecoration(
        color: railBg,
        border: Border(right: BorderSide(color: borderColor, width: 0.5)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),

          // ── 中部导航菜单项 ────────────────────────────────────────────────
          _DockNavItem(
            icon: Icons.chat_bubble_outline_rounded,
            activeIcon: Icons.chat_bubble_rounded,
            label: '消息',
            isSelected: selected == HomeSection.messages,
            badgeCount: totalUnread,
            onTap: () => onSelected(HomeSection.messages),
          ),
          const SizedBox(height: 10),
          _DockNavItem(
            icon: Icons.contacts_outlined,
            activeIcon: Icons.contacts_rounded,
            label: '通讯录',
            isSelected: selected == HomeSection.contacts,
            onTap: () => onSelected(HomeSection.contacts),
          ),
          const SizedBox(height: 10),
          _DockNavItem(
            icon: Icons.grid_view_rounded,
            activeIcon: Icons.grid_view,
            label: '工作台',
            isSelected: selected == HomeSection.workbench,
            onTap: () => onSelected(HomeSection.workbench),
          ),
          const SizedBox(height: 10),
          // 局域网快传独立入口
          _DockNavItem(
            icon: Icons.wifi_tethering_rounded,
            activeIcon: Icons.wifi_tethering_rounded,
            label: '局域网快传',
            isSelected: false,
            onTap: () {
              ref.read(windowServiceProvider).openLocalFileServer();
            },
          ),
          const SizedBox(height: 10),
          _DockNavItem(
            icon: Icons.explore_outlined,
            activeIcon: Icons.explore_rounded,
            label: '探索',
            isSelected: selected == HomeSection.explore,
            onTap: () => onSelected(HomeSection.explore),
          ),

          const Spacer(),

          // ── 底部辅助操作区 ────────────────────────────────────────────────
          // 1. 在线设备协同与管理
          Tooltip(
            message: '多端登录设备管理',
            child: _DockActionItem(
              icon: Icons.devices_rounded,
              onTap: () {
                showDialog<void>(
                  context: context,
                  builder:
                      (ctx) => Dialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: 480,
                            maxHeight: 620,
                          ),
                          child: const LoginDevicesPage(),
                        ),
                      ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          // 2. 主题切换
          Tooltip(
            message: themeMode == ThemeMode.dark ? '切换为浅色模式' : '切换为深色模式',
            child: _DockActionItem(
              icon:
                  themeMode == ThemeMode.dark
                      ? Icons.light_mode_rounded
                      : Icons.dark_mode_rounded,
              onTap:
                  () =>
                      ref
                          .read(themeModeControllerProvider.notifier)
                          .toggleTheme(),
            ),
          ),
          const SizedBox(height: 8),

          // 3. 全局设置 (独立窗口)
          Tooltip(
            message: '设置',
            child: _DockActionItem(
              icon: Icons.settings_outlined,
              onTap: () => ref.read(windowServiceProvider).openSettings(),
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, thickness: 0.5, indent: 12, endIndent: 12),
          const SizedBox(height: 12),

          // ── 最底部：当前身份头像与多身份切换入口 ────────────────────────
          Builder(
            builder: (avatarContext) {
              return Tooltip(
                message:
                    currentOwner != null
                        ? '当前身份：${currentOwner.name}\n(点击切换其它聊天身份)'
                        : '点击切换聊天身份',
                preferBelow: false,
                verticalOffset: 24,
                child: GestureDetector(
                  onTap: () {
                    final renderBox =
                        avatarContext.findRenderObject() as RenderBox?;
                    final offset = renderBox?.localToGlobal(Offset.zero);
                    DesktopChatOwnerPopover.show(
                      avatarContext,
                      controller: sessionController,
                      anchorOffset: Offset(railWidth + 8, offset?.dy ?? 20.0),
                    );
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // 主头像
                        Container(
                          padding: const EdgeInsets.all(1.5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color:
                                  otherUnread > 0
                                      ? colorScheme.error
                                      : colorScheme.primary.withValues(
                                        alpha: 0.6,
                                      ),
                              width: 1.5,
                            ),
                          ),
                          child: AppAvatar(
                            name: currentOwner?.name ?? '我',
                            imageUrl: currentOwner?.imageUrl,
                            radius: 17,
                          ),
                        ),
                        // 跨身份未读总数角标（其他身份有消息时呈现）
                        if (otherUnread > 0 || otherImmersed > 0)
                          Positioned(
                            right: -4,
                            top: -4,
                            child: AppBadge(
                              count: otherUnread,
                              dot: otherUnread == 0 && otherImmersed > 0,
                              size: AppBadgeSize.small,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }
}

class _DockNavItem extends StatelessWidget {
  const _DockNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.badgeCount = 0,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // 微信高亮风格：经典微信绿 #07C160 或主题色
    final activeColor = theme.colorScheme.primary;
    final inactiveColor =
        isDark ? const Color(0xFF909090) : const Color(0xFF5A5A5A);

    return Tooltip(
      message: label,
      preferBelow: false,
      verticalOffset: 20,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        hoverColor: isDark ? Colors.white10 : Colors.black12,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: AppBadge(
              count: badgeCount,
              size: AppBadgeSize.small,
              offset: const Offset(4, -4),
              child: Icon(
                isSelected ? activeIcon : icon,
                size: 23,
                color: isSelected ? activeColor : inactiveColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DockActionItem extends StatelessWidget {
  const _DockActionItem({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = isDark ? const Color(0xFF888888) : const Color(0xFF666666);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      hoverColor: isDark ? Colors.white10 : Colors.black12,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Center(child: Icon(icon, size: 20, color: color)),
      ),
    );
  }
}
