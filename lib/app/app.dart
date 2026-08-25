import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application_providers.dart';
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
    // Device registration is independent of user login and uses its own Basic
    // credentials. A failed background registration must never block startup.
    Future<void>.microtask(() async {
      try {
        await ref.read(deviceRegistrationApiProvider).register();
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Goto IM',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E6ED8)),
        useMaterial3: true,
      ),
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
