import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../core/compliance/privacy_consent_dialog.dart';
import '../../core/compliance/privacy_service.dart';
import '../../core/native/native.dart';
import '../../core/platform/windows/windows_window_adapter.dart';
import '../../core/services/tray_grouped_unread_provider.dart';
import '../../core/services/tray_service.dart';
import '../../core/theme/tab_glass_controller.dart';
import '../../core/widgets/app_badge.dart';
import '../../core/widgets/glass_container.dart';
import '../../features/app_update/application/app_update_service.dart';
import '../../features/home/presentation/home_sections.dart';
import '../../features/session/application/session_list_controller.dart';
import '../../features/session/presentation/chat_owner_drawer.dart';
import '../../features/workbench/application/workbench_layout_notifier.dart';
import '../layout/app_breakpoints.dart';
import 'desktop_dock_rail.dart';

/// Responsive host for the IM's top-level sections.
class ApplicationShell extends ConsumerStatefulWidget {
  const ApplicationShell({super.key});

  @override
  ConsumerState<ApplicationShell> createState() => _ApplicationShellState();
}

class _ApplicationShellState extends ConsumerState<ApplicationShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  HomeSection _section = HomeSection.messages;
  // Tabs are created on first visit only, then kept alive so switching does
  // not recreate lists, restart requests, or reset their scroll positions.
  final Set<HomeSection> _visitedSections = <HomeSection>{HomeSection.messages};
  DateTime? _lastMessagesTabTap;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WindowsWindowAdapter.setupCustomTitleBar();
    });
    Future<void>.microtask(() async {
      final privacy = ref.read(privacyServiceProvider);
      final hasAgreed = await privacy.initialize();
      if (!mounted) return;
      if (!hasAgreed) {
        final agreed = await PrivacyConsentDialog.show(
          context,
          privacyService: privacy,
        );
        if (!agreed || !mounted) return;
      }
      // A slow version check must not delay the tray needed for close-to-tray.
      // Both services start only after the existing privacy agreement check.
      if (mounted) {
        unawaited(ref.read(trayServiceProvider).initialize());
      }
      await ref
          .read(appUpdateServiceProvider)
          .checkUpdate(silent: true, context: context);
    });
  }

  void _select(HomeSection section) {
    final now = DateTime.now();
    if (section == HomeSection.messages && _section == HomeSection.messages) {
      final previous = _lastMessagesTabTap;
      _lastMessagesTabTap = now;
      if (previous != null &&
          now.difference(previous) <= const Duration(milliseconds: 450)) {
        _lastMessagesTabTap = null;
        ref.read(sessionListControllerProvider).requestFocusUnread();
      }
      return;
    }
    _lastMessagesTabTap = section == HomeSection.messages ? now : null;
    setState(() {
      _section = section;
      _visitedSections.add(section);
    });
  }

  void _openOwnerDrawer() => _scaffoldKey.currentState?.openDrawer();

  Future<void> _handlePopScope(bool didPop) async {
    if (didPop) return;

    // 1. If drawer is open, close drawer first.
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      _scaffoldKey.currentState?.closeDrawer();
      return;
    }

    // 2. If on Workbench, prioritize closing folder bubble or exiting edit mode!
    if (_section == HomeSection.workbench) {
      final workbenchState = ref.read(workbenchLayoutProvider);
      final workbenchNotifier = ref.read(workbenchLayoutProvider.notifier);

      if (workbenchState.openFolder != null) {
        workbenchNotifier.closeFolderBubble();
        return;
      }

      if (workbenchState.isEditing) {
        HapticFeedback.lightImpact();
        workbenchNotifier.toggleEditMode(false);
        return;
      }
    }

    // 3. If not on the default messages section, switch back to messages first.
    if (_section != HomeSection.messages) {
      _select(HomeSection.messages);
      return;
    }

    // 3. Minimize the app to background instead of exiting.
    final minimized = await Native.minimizeApp();
    if (!minimized) {
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 桌面端系统托盘未读数与当前身份自动同步
    ref.listen<int>(
      sessionListControllerProvider.select((state) => state.totalUnreadCount),
      (prev, next) {
        ref.read(trayServiceProvider).setUnread(next);
      },
    );
    ref.listen<String?>(
      sessionListControllerProvider.select((state) => state.currentOwner?.name),
      (prev, next) {
        ref.read(trayServiceProvider).updateContextMenu(currentOwnerName: next);
      },
    );
    ref.listen<SessionListController>(
      sessionListControllerProvider,
      (prev, next) {
        ref.read(trayGroupedUnreadProvider.notifier).syncFromRealSessions(
          currentOwner: next.currentOwner,
          allOwners: next.owners,
          sessions: next.sessions,
        );
      },
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _handlePopScope(didPop),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: Colors.transparent,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNativeDesktop =
                !kIsWeb &&
                (defaultTargetPlatform == TargetPlatform.windows ||
                    defaultTargetPlatform == TargetPlatform.macOS ||
                    defaultTargetPlatform == TargetPlatform.linux);

            final layout = AppBreakpoints.resolve(constraints.maxWidth);
            // 侧边栏一般是不隐藏，除非是小屏（窄屏手机端）
            final isCompact = !isNativeDesktop && layout == WindowLayout.mobile;
            final isDesktop = isNativeDesktop || !isCompact;
            final content = _LazyHomeSectionStack(
              selected: _section,
              visited: _visitedSections,
              isCompact: isCompact,
              isDesktop: isDesktop,
              onOpenOwnerDrawer: _openOwnerDrawer,
            );

            return Scaffold(
              key: _scaffoldKey,
              extendBody: true,
              resizeToAvoidBottomInset: false,
              drawer:
                  isCompact
                      ? ChatOwnerDrawer(
                        controller: ref.watch(sessionListControllerProvider),
                      )
                      : null,
              body:
                  isCompact
                      ? content
                      : Column(
                          children: [
                            if (isNativeDesktop)
                              const _DesktopMainWindowTitleBar(),
                            Expanded(
                              child: Row(
                                children: [
                                  DesktopDockRail(
                                    selected: _section,
                                    onSelected: _select,
                                  ),
                                  Expanded(child: content),
                                ],
                              ),
                            ),
                          ],
                        ),
              bottomNavigationBar:
                  isCompact
                      ? _HomeNavigationBar(
                        selected: _section,
                        onSelected: _select,
                      )
                      : null,
            );
          },
        ),
      ),
    );
  }
}

/// Non-PageView tab host: pages are lazy-created and their state is retained.
///
/// [Offstage] avoids painting inactive lists, while [TickerMode] pauses their
/// animations. This keeps a tab switch lightweight without eager-initing all
/// five top-level pages.
class _LazyHomeSectionStack extends StatelessWidget {
  const _LazyHomeSectionStack({
    required this.selected,
    required this.visited,
    required this.isCompact,
    this.isDesktop = false,
    required this.onOpenOwnerDrawer,
  });

  final HomeSection selected;
  final Set<HomeSection> visited;
  final bool isCompact;
  final bool isDesktop;
  final VoidCallback onOpenOwnerDrawer;

  @override
  Widget build(BuildContext context) {
    final sections = HomeSection.values
        .where(visited.contains)
        .toList(growable: false);
    return Stack(
      fit: StackFit.expand,
      children: sections
          .map(
            (section) => Offstage(
              offstage: section != selected,
              child: TickerMode(
                enabled: section == selected,
                child: HomeSectionPage(
                  key: PageStorageKey<String>('home-section-${section.name}'),
                  section: section,
                  isCompact: isCompact,
                  isDesktop: isDesktop,
                  onOpenOwnerDrawer: onOpenOwnerDrawer,
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _HomeNavigationBar extends ConsumerWidget {
  const _HomeNavigationBar({required this.selected, required this.onSelected});

  final HomeSection selected;
  final ValueChanged<HomeSection> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isGlass = ref.watch(tabGlassProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomSafe = MediaQuery.paddingOf(context).bottom;
    final totalUnread =
        ref.watch(sessionListControllerProvider).totalUnreadCount;
    // 微信风格毛玻璃背景：半透明底色让 BackdropFilter 模糊效果可见
    // alpha ≈ 0xA8 (66%) — 足够透光看到滑过内容的模糊，又不至于完全透明
    final glassColor =
        isGlass
            ? (isDark ? const Color(0xA8181818) : const Color(0xA8F7F7F7))
            : (isDark ? theme.colorScheme.surface : const Color(0xFFF7F7F7));

    final dividerColor =
        isDark ? const Color(0x33FFFFFF) : const Color(0x1A000000);

    final unselectedColor =
        isDark ? const Color(0xFFA0A0A0) : const Color(0xFF262626);

    return GlassContainer(
      borderRadius: BorderRadius.zero,
      borderWidth: 0,
      blurSigma: isGlass ? 20.0 : 0.0,
      backgroundColor: glassColor,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: dividerColor, width: 0.5)),
        ),
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomSafe),
          child: SizedBox(
            height: kHomeBottomBarHeight,
            child: Row(
              children: HomeSection.values
                  .map((section) {
                    final isSelected = section == selected;
                    final unreadCount =
                        section == HomeSection.messages ? totalUnread : 0;
                    final activeColor = theme.colorScheme.primary;

                    return Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onSelected(section),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AppBadge(
                              count: unreadCount,
                              size: AppBadgeSize.small,
                              offset: const Offset(4, -3),
                              child: Icon(
                                isSelected
                                    ? section.selectedIcon
                                    : section.icon,
                                size: 24,
                                color:
                                    isSelected ? activeColor : unselectedColor,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              section.label,
                              style: TextStyle(
                                fontSize: 10.5,
                                height: 1.1,
                                fontWeight:
                                    isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                color:
                                    isSelected ? activeColor : unselectedColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  })
                  .toList(growable: false),
            ),
          ),
        ),
      ),
    );
  }
}

/// 桌面端主窗口无边框自定义标题栏 (沉浸式顶栏 + 窗口三按钮)
class _DesktopMainWindowTitleBar extends StatefulWidget {
  const _DesktopMainWindowTitleBar();

  @override
  State<_DesktopMainWindowTitleBar> createState() =>
      _DesktopMainWindowTitleBarState();
}

class _DesktopMainWindowTitleBarState
    extends State<_DesktopMainWindowTitleBar> {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _isMaximized = WindowsWindowAdapter.isMaximized();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFECECEC);
    final borderColor =
        isDark ? const Color(0x1FFFFFFF) : const Color(0x1F000000);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => WindowsWindowAdapter.startDragging(),
      onDoubleTap: () {
        WindowsWindowAdapter.toggleMaximize();
        if (mounted) {
          setState(() {
            _isMaximized = WindowsWindowAdapter.isMaximized();
          });
        }
      },
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: bg,
          border: Border(bottom: BorderSide(color: borderColor, width: 0.5)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.chat_bubble_rounded,
              size: 15,
              color: Color(0xFF07C160),
            ),
            const SizedBox(width: 8),
            Text(
              'Goto IM',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const Spacer(),
            // 最小化按钮
            IconButton(
              icon: const Icon(Icons.remove_rounded, size: 14),
              tooltip: '最小化',
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () => WindowsWindowAdapter.minimize(),
            ),
            const SizedBox(width: 2),
            // 最大化/还原按钮
            IconButton(
              icon: Icon(
                _isMaximized
                    ? Icons.filter_none_rounded
                    : Icons.crop_square_rounded,
                size: 13,
              ),
              tooltip: _isMaximized ? '还原' : '最大化',
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () {
                WindowsWindowAdapter.toggleMaximize();
                if (mounted) {
                  setState(() {
                    _isMaximized = WindowsWindowAdapter.isMaximized();
                  });
                }
              },
            ),
            const SizedBox(width: 2),
            // 关闭按钮
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 15),
              tooltip: '关闭',
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () => WindowsWindowAdapter.close(),
            ),
          ],
        ),
      ),
    );
  }
}
