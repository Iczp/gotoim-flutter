import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../core/compliance/privacy_consent_dialog.dart';
import '../../core/compliance/privacy_service.dart';
import '../../core/native/native.dart';
import '../../core/theme/tab_glass_controller.dart';
import '../../core/widgets/app_badge.dart';
import '../../core/widgets/glass_container.dart';
import '../../features/app_update/application/app_update_service.dart';
import '../../features/home/presentation/home_sections.dart';
import '../../features/session/application/session_list_controller.dart';
import '../../features/session/presentation/chat_owner_drawer.dart';
import '../../features/workbench/application/workbench_layout_notifier.dart';
import '../layout/app_breakpoints.dart';

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
      // After privacy agreement is confirmed, perform silent app version check
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
            final layout = AppBreakpoints.resolve(constraints.maxWidth);
            final isCompact = layout == WindowLayout.mobile;
            final content = _LazyHomeSectionStack(
              selected: _section,
              visited: _visitedSections,
              isCompact: isCompact,
              onOpenOwnerDrawer: _openOwnerDrawer,
            );

            return Scaffold(
              key: _scaffoldKey,
              extendBody: true,
              resizeToAvoidBottomInset: false,
              drawer: ChatOwnerDrawer(
                controller: ref.watch(sessionListControllerProvider),
              ),
              body:
                  isCompact
                      ? content
                      : Row(
                        children: [
                          _HomeNavigationRail(
                            selected: _section,
                            extended: layout == WindowLayout.desktop,
                            onSelected: _select,
                          ),
                          const VerticalDivider(width: 1),
                          Expanded(child: content),
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
    required this.onOpenOwnerDrawer,
  });

  final HomeSection selected;
  final Set<HomeSection> visited;
  final bool isCompact;
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

    // 微信风格毛玻璃背景：浅色微乳灰白透光，深色暗黑微透光
    final glassColor = isGlass
        ? (isDark ? const Color(0xE6191919) : const Color(0xE6F7F7F7))
        : (isDark ? theme.colorScheme.surface : const Color(0xFFF7F7F7));

    final dividerColor = isDark
        ? const Color(0x26FFFFFF)
        : const Color(0x26000000);

    final unselectedColor = isDark
        ? const Color(0xFFA0A0A0)
        : const Color(0xFF262626);

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
              children: HomeSection.values.map((section) {
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
                            isSelected ? section.selectedIcon : section.icon,
                            size: 24,
                            color: isSelected ? activeColor : unselectedColor,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          section.label,
                          style: TextStyle(
                            fontSize: 10.5,
                            height: 1.1,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w400,
                            color: isSelected ? activeColor : unselectedColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(growable: false),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeNavigationRail extends ConsumerWidget {
  const _HomeNavigationRail({
    required this.selected,
    required this.extended,
    required this.onSelected,
  });

  final HomeSection selected;
  final bool extended;
  final ValueChanged<HomeSection> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isGlass = ref.watch(tabGlassProvider);
    final theme = Theme.of(context);
    final totalUnread =
        ref.watch(sessionListControllerProvider).totalUnreadCount;
    return GlassContainer(
      borderRadius: BorderRadius.zero,
      borderWidth: 0,
      blurSigma: isGlass ? null : 0.0,
      backgroundColor: isGlass ? null : theme.colorScheme.surface,
      child: NavigationRail(
        backgroundColor: Colors.transparent,
        extended: extended,
        minExtendedWidth: 180,
        selectedIndex: HomeSection.values.indexOf(selected),
        onDestinationSelected: (index) => onSelected(HomeSection.values[index]),
        labelType: extended ? null : NavigationRailLabelType.all,
        destinations:
            HomeSection.values.map((section) {
              final icon = Icon(section.icon);
              final selectedIcon = Icon(section.selectedIcon);
              final unreadCount =
                  section == HomeSection.messages ? totalUnread : 0;
              return NavigationRailDestination(
                icon: AppBadge(
                  count: unreadCount,
                  size: AppBadgeSize.small,
                  offset: const Offset(4, -4),
                  child: icon,
                ),
                selectedIcon: AppBadge(
                  count: unreadCount,
                  size: AppBadgeSize.small,
                  offset: const Offset(4, -4),
                  child: selectedIcon,
                ),
                label: Text(section.label),
              );
            }).toList(),
      ),
    );
  }
}
