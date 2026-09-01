import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../core/widgets/glass_container.dart';
import '../../features/home/presentation/home_sections.dart';
import '../../features/session/application/session_list_controller.dart';
import '../../features/session/presentation/chat_owner_drawer.dart';
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
  DateTime? _lastBackPressTime;

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

    // 2. If not on the default messages section, switch back to messages first.
    if (_section != HomeSection.messages) {
      _select(HomeSection.messages);
      return;
    }

    // 3. Double-tap back within 2 seconds to exit the app.
    final now = DateTime.now();
    if (_lastBackPressTime == null ||
        now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
      _lastBackPressTime = now;
      if (mounted) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('再按一次退出应用'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // 与工作台 AppBar 及各 Tab 的页面内标题栏使用同一主题色，避免色差。
    final headerColor = theme.colorScheme.surface;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _handlePopScope(didPop),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: headerColor,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
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

class _HomeNavigationBar extends StatelessWidget {
  const _HomeNavigationBar({required this.selected, required this.onSelected});

  final HomeSection selected;
  final ValueChanged<HomeSection> onSelected;

  @override
  Widget build(BuildContext context) {
    final dividerColor = Theme.of(context).dividerColor.withValues(alpha: .55);
    return GlassContainer(
      borderRadius: BorderRadius.zero,
      borderWidth: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: dividerColor, width: .8)),
        ),
        child: NavigationBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedIndex: HomeSection.values.indexOf(selected),
          onDestinationSelected:
              (index) => onSelected(HomeSection.values[index]),
          destinations:
              HomeSection.values
                  .map(
                    (section) => NavigationDestination(
                      icon: Icon(section.icon),
                      selectedIcon: Icon(section.selectedIcon),
                      label: section.label,
                    ),
                  )
                  .toList(),
        ),
      ),
    );
  }
}

class _HomeNavigationRail extends StatelessWidget {
  const _HomeNavigationRail({
    required this.selected,
    required this.extended,
    required this.onSelected,
  });

  final HomeSection selected;
  final bool extended;
  final ValueChanged<HomeSection> onSelected;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      borderRadius: BorderRadius.zero,
      borderWidth: 0,
      child: NavigationRail(
        backgroundColor: Colors.transparent,
        extended: extended,
        minExtendedWidth: 180,
        selectedIndex: HomeSection.values.indexOf(selected),
        onDestinationSelected: (index) => onSelected(HomeSection.values[index]),
        labelType: extended ? null : NavigationRailLabelType.all,
        destinations:
            HomeSection.values
                .map(
                  (section) => NavigationRailDestination(
                    icon: Icon(section.icon),
                    selectedIcon: Icon(section.selectedIcon),
                    label: Text(section.label),
                  ),
                )
                .toList(),
      ),
    );
  }
}
