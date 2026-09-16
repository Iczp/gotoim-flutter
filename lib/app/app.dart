import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/font_scale_controller.dart';
import '../core/theme/overscroll_style_controller.dart';
import '../core/theme/theme_mode_controller.dart';
import '../core/floating_window/floating_window.dart';
import '../core/widgets/app_scroll_behavior.dart';
import '../features/session/application/realtime_sync_coordinator.dart';
import '../features/session/application/presence_heartbeat_coordinator.dart';
import '../features/session/application/friend_presence_store.dart';
import '../features/session/application/active_chat_registry.dart';
import '../features/session/application/message_alert_settings.dart';
import 'application_providers.dart';
import 'app_navigation.dart';
import 'router/app_router.dart';

class GotoImApp extends ConsumerStatefulWidget {
  const GotoImApp({super.key});

  @override
  ConsumerState<GotoImApp> createState() => _GotoImAppState();
}

class _GotoImAppState extends ConsumerState<GotoImApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(ref.read(messageAlertSettingsProvider).initialize());
    ref.read(realtimeSyncCoordinatorProvider).start();
    ref.read(presenceHeartbeatCoordinatorProvider).start();
    ref.read(friendPresenceStoreProvider).start();
    // Device registration is independent of user login and uses a dedicated
    // client-credentials token. A failed registration must never block startup.
    Future<void>.microtask(() async {
      try {
        await ref.read(deviceRegistrationApiProvider).register();
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      ref.read(activeChatRegistryProvider).updateLifecycle(state);

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final overscrollStyle = ref.watch(overscrollStyleProvider);
    final fontScale = ref.watch(fontScaleProvider);

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
        final mediaQuery =
            MediaQuery.maybeOf(context) ??
            MediaQueryData.fromView(View.of(context));
        final scaledMediaQuery = mediaQuery.copyWith(
          textScaler: TextScaler.linear(fontScale),
        );

        return MediaQuery(
          data: scaledMediaQuery,
          child: FloatingWindowScope(
            manager: manager,
            child: Stack(
              children: [
                child ?? const SizedBox.shrink(),
                FloatingWindowLayer(manager: manager),
              ],
            ),
          ),
        );
      },
    );
  }
}
