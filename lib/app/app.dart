import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/overscroll_style_controller.dart';
import '../core/theme/theme_mode_controller.dart';
import '../core/floating_window/floating_window.dart';
import '../core/widgets/app_scroll_behavior.dart';
import '../features/session/application/realtime_sync_coordinator.dart';
import 'application_providers.dart';
import 'app_navigation.dart';
import 'router/app_router.dart';

class GotoImApp extends ConsumerStatefulWidget {
  const GotoImApp({super.key});

  @override
  ConsumerState<GotoImApp> createState() => _GotoImAppState();
}

class _GotoImAppState extends ConsumerState<GotoImApp> {
  @override
  void initState() {
    super.initState();
    ref.read(realtimeSyncCoordinatorProvider).start();
    // Device registration is independent of user login and uses a dedicated
    // client-credentials token. A failed registration must never block startup.
    Future<void>.microtask(() async {
      try {
        await ref.read(deviceRegistrationApiProvider).register();
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final overscrollStyle = ref.watch(overscrollStyleProvider);

    return MaterialApp.router(
      title: 'Goto IM',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: themeMode,
      scrollBehavior: AppScrollBehavior(style: overscrollStyle),
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      routerConfig: ref.watch(appRouterProvider),
      builder: (context, child) {
        final manager = ref.read(floatingWindowManagerProvider);
        return FloatingWindowScope(
          manager: manager,
          child: Stack(
            children: [
              child ?? const SizedBox.shrink(),
              FloatingWindowLayer(manager: manager),
            ],
          ),
        );
      },
    );
  }
}
