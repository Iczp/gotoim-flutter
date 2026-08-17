import 'package:go_router/go_router.dart';

import '../shell/application_shell.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const ApplicationShell(),
    ),
  ],
);
