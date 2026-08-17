import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_environment.dart';
import '../../core/platform/platform_facade.dart';
import '../../features/auth/application/auth_controller.dart';
import '../layout/app_breakpoints.dart';

/// A platform-neutral host for future feature routes.
///
/// It intentionally contains no migrated IM business page or business state.
class ApplicationShell extends ConsumerWidget {
  const ApplicationShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platform = ref.watch(platformFacadeProvider);
    final environment = ref.watch(appEnvironmentProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = AppBreakpoints.resolve(constraints.maxWidth);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Goto IM'),
            actions: [
              IconButton(
                tooltip: '连接测试',
                icon: const Icon(Icons.network_check),
                onPressed: () => context.go('/diagnostics/connection'),
              ),
              IconButton(
                tooltip: '退出登录',
                icon: const Icon(Icons.logout),
                onPressed: () => ref.read(authControllerProvider).logout(),
              ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Cross-platform foundation ready\n'
                  'environment: ${environment.flavor.name}\n'
                  'runtime: ${platform.kind.name}\n'
                  'layout: ${layout.name}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
