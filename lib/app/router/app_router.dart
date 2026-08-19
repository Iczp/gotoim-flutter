import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/presentation/auth_loading_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/scan_login/presentation/scan_login_confirmation_page.dart';
import '../../features/scan_login/presentation/scan_login_scan_page.dart';
import '../../features/diagnostics/presentation/connection_test_page.dart';
import '../../features/diagnostics/presentation/auth_diagnostics_page.dart';
import '../../features/diagnostics/presentation/diagnostics_home_page.dart';
import '../../features/diagnostics/presentation/local_notification_diagnostics_page.dart';
import '../../features/diagnostics/presentation/signalr_diagnostics_page.dart';
import '../../features/diagnostics/presentation/scan_code_diagnostics_page.dart';
import '../shell/application_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authControllerProvider);
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: auth,
    redirect: (context, state) {
      final location = state.uri.path;
      if (auth.status == AuthStatus.checking) {
        return location == '/splash' ? null : '/splash';
      }
      if (auth.status == AuthStatus.authenticated) {
        return location == '/login' || location == '/splash' ? '/' : null;
      }
      return location == '/login' ? null : '/login';
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const ApplicationShell()),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(
        path: '/scan-login',
        builder: (context, state) {
          final scanText = state.uri.queryParameters['scanText'] ?? '';
          return ScanLoginConfirmationPage(scanText: scanText);
        },
      ),
      GoRoute(
        path: '/scan-login/scan',
        builder: (context, state) => const ScanLoginScanPage(),
      ),
      GoRoute(
        path: '/splash',
        builder: (context, state) => const AuthLoadingPage(),
      ),
      GoRoute(
        path: '/diagnostics',
        builder: (context, state) => const DiagnosticsHomePage(),
      ),
      GoRoute(
        path: '/diagnostics/auth',
        builder: (context, state) => const AuthDiagnosticsPage(),
      ),
      GoRoute(
        path: '/diagnostics/api',
        builder: (context, state) => const ConnectionTestPage(),
      ),
      GoRoute(
        path: '/diagnostics/signalr',
        builder: (context, state) => const SignalRDiagnosticsPage(),
      ),
      GoRoute(
        path: '/diagnostics/notifications',
        builder: (context, state) => const LocalNotificationDiagnosticsPage(),
      ),
      GoRoute(
        path: '/diagnostics/scan-code',
        builder: (context, state) => const ScanCodeDiagnosticsPage(),
      ),
    ],
  );
});
