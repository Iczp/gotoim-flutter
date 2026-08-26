import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_environment.dart';
import '../../core/platform/platform_facade.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/home/presentation/home_sections.dart';
import '../layout/app_breakpoints.dart';

/// Responsive host for the IM's top-level sections.
class ApplicationShell extends ConsumerStatefulWidget {
  const ApplicationShell({super.key});

  @override
  ConsumerState<ApplicationShell> createState() => _ApplicationShellState();
}

class _ApplicationShellState extends ConsumerState<ApplicationShell> {
  HomeSection _section = HomeSection.messages;

  void _select(HomeSection section) => setState(() => _section = section);

  @override
  Widget build(BuildContext context) {
    final platform = ref.watch(platformFacadeProvider);
    final environment = ref.watch(appEnvironmentProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = AppBreakpoints.resolve(constraints.maxWidth);
        final isCompact = layout == WindowLayout.mobile;
        final content = HomeSectionPage(
          section: _section,
          isCompact: isCompact,
        );

        return Scaffold(
          appBar: _HomeAppBar(
            title: _section.label,
            platformLabel: '${environment.flavor.name} · ${platform.kind.name}',
          ),
          body: isCompact
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
          bottomNavigationBar: isCompact
              ? _HomeNavigationBar(selected: _section, onSelected: _select)
              : null,
        );
      },
    );
  }
}

class _HomeAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const _HomeAppBar({required this.title, required this.platformLabel});

  final String title;
  final String platformLabel;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppBar(
      title: Text(title),
      actions: [
        IconButton(
          tooltip: '局域网文件管理',
          icon: const Icon(Icons.folder_shared_outlined),
          onPressed: () => context.push('/local-file-server'),
        ),
        if (kDebugMode)
          IconButton(
            tooltip: '开发诊断中心 ($platformLabel)',
            icon: const Icon(Icons.network_check),
            onPressed: () => context.push('/diagnostics'),
          ),
        IconButton(
          tooltip: '扫码登录',
          icon: const Icon(Icons.qr_code_scanner_outlined),
          onPressed: () => context.push('/scan-login/scan'),
        ),
        IconButton(
          tooltip: '退出登录',
          icon: const Icon(Icons.logout),
          onPressed: () => ref.read(authControllerProvider).logout(),
        ),
      ],
    );
  }
}

class _HomeNavigationBar extends StatelessWidget {
  const _HomeNavigationBar({required this.selected, required this.onSelected});

  final HomeSection selected;
  final ValueChanged<HomeSection> onSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: HomeSection.values.indexOf(selected),
      onDestinationSelected: (index) => onSelected(HomeSection.values[index]),
      destinations: HomeSection.values
          .map(
            (section) => NavigationDestination(
              icon: Icon(section.icon),
              selectedIcon: Icon(section.selectedIcon),
              label: section.label,
            ),
          )
          .toList(),
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
    return NavigationRail(
      extended: extended,
      minExtendedWidth: 180,
      selectedIndex: HomeSection.values.indexOf(selected),
      onDestinationSelected: (index) => onSelected(HomeSection.values[index]),
      labelType: extended ? null : NavigationRailLabelType.all,
      destinations: HomeSection.values
          .map(
            (section) => NavigationRailDestination(
              icon: Icon(section.icon),
              selectedIcon: Icon(section.selectedIcon),
              label: Text(section.label),
            ),
          )
          .toList(),
    );
  }
}
