import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/platform_facade.dart';
import '../layout/app_breakpoints.dart';

/// A platform-neutral host for future feature routes.
///
/// It intentionally contains no migrated IM business page or business state.
class ApplicationShell extends ConsumerWidget {
  const ApplicationShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platform = ref.watch(platformFacadeProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = AppBreakpoints.resolve(constraints.maxWidth);
        return Scaffold(
          appBar: AppBar(title: const Text('Goto IM')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Cross-platform foundation ready\n'
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
