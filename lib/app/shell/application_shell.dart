import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../core/widgets/glass_container.dart';
import '../../features/home/presentation/home_sections.dart';
import '../../features/session/application/session_list_controller.dart';
import '../../features/session/presentation/session_list_page.dart';
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
  DateTime? _lastMessagesTabTap;

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
    setState(() => _section = section);
  }

  void _openOwnerDrawer() => _scaffoldKey.currentState?.openDrawer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final headerColor = theme.colorScheme.surfaceContainerHighest;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: headerColor,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final layout = AppBreakpoints.resolve(constraints.maxWidth);
          final isCompact = layout == WindowLayout.mobile;
          final content = HomeSectionPage(
            section: _section,
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
