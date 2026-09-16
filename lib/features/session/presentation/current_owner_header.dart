import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/scan/unified_scan_dispatcher.dart';
import '../data/models/chat_owner.dart';
import 'chat_object_avatar.dart';

/// Header displaying the current chat identity / owner with actions on the trailing side.
class CurrentOwnerHeader extends ConsumerWidget {
  const CurrentOwnerHeader({
    required this.owner,
    required this.hasMultiple,
    required this.isConnecting,
    required this.onPressed,
    super.key,
  });

  final ChatOwner? owner;
  final bool hasMultiple;
  final bool isConnecting;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SizedBox(
      height: 56,
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              // 左侧身份切换区域
              Expanded(
                child: InkWell(
                  onTap: onPressed,
                  borderRadius: BorderRadius.circular(24),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        ChatObjectAvatar(
                          name: owner?.name ?? '-',
                          imageUrl: owner?.imageUrl,
                          radius: 18,
                          chatObjectId: owner?.id,
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            owner?.name ?? 'Goto IM',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (hasMultiple)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // 右侧操作按钮：搜索与 + 号菜单
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.search_rounded),
                    tooltip: '搜索',
                    onPressed: () => context.push('/search'),
                  ),
                  Builder(
                    builder: (buttonContext) {
                      return IconButton(
                        icon: const Icon(Icons.add_circle_outline_rounded),
                        tooltip: '更多功能',
                        onPressed:
                            () => _showAddMenu(buttonContext, context, ref),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddMenu(
    BuildContext buttonContext,
    BuildContext pageContext,
    WidgetRef ref,
  ) {
    final renderBox = buttonContext.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;
    final origin = renderBox.localToGlobal(Offset.zero);
    final targetRect = origin & renderBox.size;

    Navigator.of(pageContext, rootNavigator: true).push(
      _HeaderMenuRoute(
        targetRect: targetRect,
        onSelected: (value) {
          switch (value) {
            case 'scan':
              ref
                  .read(unifiedScanDispatcherProvider)
                  .openAndDispatch(pageContext, ref);
            case 'add_friend':
              pageContext.push('/add-friend');
            case 'create_group':
              pageContext.push('/create-group');
          }
        },
      ),
    );
  }
}

class _HeaderMenuRoute extends PopupRoute<void> {
  _HeaderMenuRoute({required this.targetRect, required this.onSelected});

  final Rect targetRect;
  final ValueChanged<String> onSelected;

  @override
  Color? get barrierColor => Colors.transparent;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => '关闭菜单';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 140);

  @override
  Widget buildModalBarrier() {
    // 触摸屏幕其他任意位置时立即隐藏菜单，无需等待完整的点击抬起
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => navigator?.pop(),
      child: const SizedBox.expand(),
    );
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mediaQuery = MediaQuery.of(context);

    // 靠右侧对齐，紧贴 + 号按钮下方
    const menuWidth = 148.0;
    final top = targetRect.bottom + 6;
    final right = (mediaQuery.size.width - targetRect.right).clamp(8.0, 40.0);

    return Stack(
      children: [
        Positioned(
          top: top,
          right: right,
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              alignment: Alignment.topRight,
              child: Material(
                elevation: 6,
                shadowColor: Colors.black26,
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  width: menuWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _MenuItem(
                        icon: Icons.qr_code_scanner_rounded,
                        text: '扫一扫',
                        onTap: () {
                          Navigator.of(context).pop();
                          onSelected('scan');
                        },
                      ),
                      Divider(
                        height: 1,
                        color: theme.dividerColor.withValues(alpha: 0.2),
                      ),
                      _MenuItem(
                        icon: Icons.person_add_outlined,
                        text: '添加好友',
                        onTap: () {
                          Navigator.of(context).pop();
                          onSelected('add_friend');
                        },
                      ),
                      Divider(
                        height: 1,
                        color: theme.dividerColor.withValues(alpha: 0.2),
                      ),
                      _MenuItem(
                        icon: Icons.group_add_outlined,
                        text: '创建群聊',
                        onTap: () {
                          Navigator.of(context).pop();
                          onSelected('create_group');
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.text,
    required this.onTap,
  });

  final IconData icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.onSurface),
            const SizedBox(width: 12),
            Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
