import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/presentation/auth_loading_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/diagnostics/presentation/connection_test_page.dart';
import '../shell/application_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authControllerProvider);
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: auth,
    redirect: (context, state) {
      final location = state.location;
      if (auth.status == AuthStatus.checking) {
        return location == '/splash' ? null : '/splash';
      }
      if (auth.status == AuthStatus.authenticated) {
        return location == '/login' || location == '/splash' ? '/' : null;
      }
      return location == '/login' ? null : '/login';
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const ApplicationShell(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/splash',
        builder: (context, state) => const AuthLoadingPage(),
      ),
      GoRoute(
        path: '/diagnostics/connection',
        builder: (context, state) => const ConnectionTestPage(),
      ),
    ],
  );
});
