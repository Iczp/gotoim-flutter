import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_mode_controller.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/glass_container.dart';
import '../application/session_list_controller.dart';
import '../data/models/chat_owner.dart';
import 'chat_owner_drawer.dart';

/// 桌面端“切换聊天身份”弹出浮窗 (DesktopChatOwnerPopover)
///
/// 遵循微信 4.0 桌面端交互设计：
/// 1. 点击 Dock 栏左上角头像或会话顶栏身份胶囊时，向右呼出轻量级毛玻璃浮窗；
/// 2. 清晰展示当前用户绑定的全部聊天身份（如普通个人、官方客服、企业门店等）；
/// 3. 每个身份卡片展示独立未读数红点/角标，支持单窗口内秒级切换；
/// 4. 底部显示当前 ABP 登录主账号与个人中心入口。
class DesktopChatOwnerPopover extends ConsumerWidget {
  const DesktopChatOwnerPopover({required this.controller, super.key});

  final SessionListController controller;

  static Future<void> show(
    BuildContext context, {
    required SessionListController controller,
    Offset? anchorOffset,
  }) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      _OwnerPopoverRoute(
        builder: (dialogContext) {
          final theme = Theme.of(dialogContext);
          final isDark = theme.brightness == Brightness.dark;
          final screenSize = MediaQuery.of(dialogContext).size;
          final left = anchorOffset?.dx ?? 72.0;
          final bool isNearBottom =
              anchorOffset != null &&
              anchorOffset.dy > screenSize.height * 0.55;
          final double? top =
              isNearBottom
                  ? null
                  : (anchorOffset?.dy ?? 20.0).clamp(
                    16.0,
                    screenSize.height - 120,
                  );
          final double? bottom =
              isNearBottom
                  ? (screenSize.height - anchorOffset.dy - 40).clamp(
                    16.0,
                    screenSize.height - 200,
                  )
                  : null;

          return Stack(
            children: [
              Positioned(
                left: left,
                top: top,
                bottom: bottom,
                child: Material(
                  color: Colors.transparent,
                  child: GlassContainer(
                    borderRadius: BorderRadius.circular(14),
                    borderWidth: 1,
                    blurSigma: 24,
                    backgroundColor:
                        isDark
                            ? const Color(0xE6252525)
                            : const Color(0xF2FFFFFF),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 280,
                        maxWidth: 320,
                        maxHeight: 520,
                      ),
                      child: DesktopChatOwnerPopover(controller: controller),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final themeMode = ref.watch(themeModeProvider);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 浮窗头部
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
          child: Row(
            children: [
              Text(
                '切换聊天身份',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              // 快速切换深色 / 浅色模式
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '切换深浅主题',
                icon: Icon(
                  themeMode == ThemeMode.dark
                      ? Icons.dark_mode_rounded
                      : themeMode == ThemeMode.light
                      ? Icons.light_mode_rounded
                      : Icons.brightness_auto_rounded,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
                onPressed:
                    () =>
                        ref
                            .read(themeModeControllerProvider.notifier)
                            .toggleTheme(),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '关闭',
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 0.5),

        // 身份卡片列表
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            children: [
              for (final owner in controller.owners)
                _OwnerCard(
                  owner: owner,
                  isCurrent: controller.currentOwner?.id == owner.id,
                  isDark: isDark,
                  onSelect: () async {
                    Navigator.of(context).pop();
                    await controller.selectOwner(owner);
                  },
                ),
            ],
          ),
        ),

        const Divider(height: 1, thickness: 0.5),

        // 底部当前主账号信息
        CurrentUserAccountTile(controller: controller),
        const SizedBox(height: 4),
      ],
    );
  }
}

/// A local popover must not hide native docked panes like a modal dialog does.
class _OwnerPopoverRoute extends PopupRoute<void> {
  _OwnerPopoverRoute({required this.builder});

  final WidgetBuilder builder;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String get barrierLabel => '关闭身份切换';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 120);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => SafeArea(child: builder(context));

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(opacity: animation, child: child);
}

class _OwnerCard extends StatelessWidget {
  const _OwnerCard({
    required this.owner,
    required this.isCurrent,
    required this.isDark,
    required this.onSelect,
  });

  final ChatOwner owner;
  final bool isCurrent;
  final bool isDark;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final activeBg =
        isDark
            ? colorScheme.primary.withValues(alpha: 0.18)
            : colorScheme.primary.withValues(alpha: 0.12);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: isCurrent ? activeBg : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          leading: Stack(
            clipBehavior: Clip.none,
            children: [
              AppAvatar(name: owner.name, imageUrl: owner.imageUrl, radius: 18),
              if (owner.typeDescription.isNotEmpty)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      owner.typeDescription.contains('客服')
                          ? Icons.support_agent_rounded
                          : Icons.person_rounded,
                      size: 11,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  owner.name,
                  style: TextStyle(
                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 13.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isCurrent)
                Icon(
                  Icons.check_circle_rounded,
                  size: 16,
                  color: colorScheme.primary,
                ),
            ],
          ),
          subtitle: Row(
            children: [
              if (owner.typeDescription.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color:
                        isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    owner.typeDescription,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              const Spacer(),
              if (!isCurrent &&
                  (owner.unreadCount > 0 || owner.immersedCount > 0))
                AppBadge(
                  count: owner.unreadCount,
                  dot: owner.unreadCount == 0 && owner.immersedCount > 0,
                  size: AppBadgeSize.small,
                ),
            ],
          ),
          onTap: onSelect,
        ),
      ),
    );
  }
}
