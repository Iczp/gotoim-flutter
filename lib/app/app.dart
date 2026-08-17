import 'package:flutter/material.dart';

import 'router/app_router.dart';

class GotoImApp extends StatelessWidget {
  const GotoImApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Goto IM',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E6ED8)),
        useMaterial3: true,
      ),
      routerConfig: appRouter,
    );
  }
}
