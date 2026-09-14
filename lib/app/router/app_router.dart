import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/presentation/auth_loading_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/scan_login/presentation/scan_login_confirmation_page.dart';
import '../../features/scan_login/presentation/scan_login_scan_page.dart';
import '../../features/diagnostics/presentation/connection_test_page.dart';
import '../../features/diagnostics/presentation/abp_configuration_diagnostics_page.dart';
import '../../features/diagnostics/presentation/auth_diagnostics_page.dart';
import '../../features/diagnostics/presentation/diagnostics_home_page.dart';
import '../../features/diagnostics/presentation/local_notification_diagnostics_page.dart';
import '../../features/diagnostics/presentation/signalr_diagnostics_page.dart';
import '../../features/diagnostics/presentation/scan_code_diagnostics_page.dart';
import '../../features/diagnostics/presentation/client_capabilities_diagnostics_page.dart';
import '../../features/diagnostics/presentation/js_bridge_diagnostics_page.dart';
import '../../features/diagnostics/presentation/media_diagnostics_page.dart';
import '../../features/diagnostics/presentation/media_preview_diagnostics_page.dart';
import '../../features/diagnostics/presentation/floating_window_diagnostics_page.dart';
import '../../features/diagnostics/presentation/webview_session_diagnostics_page.dart';
import '../../features/user/presentation/avatar_settings_page.dart';
import '../../features/mine/presentation/account_management_page.dart';
import '../../features/diagnostics/presentation/js_bridge_harness_page.dart';
import '../../features/diagnostics/presentation/database_diagnostics_page.dart';
import '../../features/diagnostics/presentation/session_list_diagnostics_page.dart';
import '../../features/diagnostics/presentation/chat_diagnostics_page.dart';
import '../../features/diagnostics/presentation/chat_bubble_diagnostics_page.dart';
import '../../features/diagnostics/presentation/app_task_diagnostics_page.dart';
import '../../features/diagnostics/presentation/deep_link_diagnostics_page.dart';
import '../../features/diagnostics/presentation/native_diagnostics_page.dart';
import '../../features/diagnostics/presentation/device_registration_diagnostics_page.dart';
import '../../features/diagnostics/presentation/theme_diagnostics_page.dart';
import '../../features/diagnostics/presentation/half_page_sheet_diagnostics_page.dart';
import '../../features/diagnostics/presentation/adaptive_page_diagnostics_page.dart';
import '../../features/diagnostics/presentation/toast_diagnostics_page.dart';
import '../../features/diagnostics/presentation/modal_diagnostics_page.dart';
import '../../features/diagnostics/presentation/target_picker_diagnostics_page.dart';
import '../../features/diagnostics/presentation/remote_devtools_diagnostics_page.dart';
import '../../features/diagnostics/presentation/workbench_layout_diagnostics_page.dart';
import '../../features/local_file_server/pages/local_file_server_page.dart';
import '../../features/local_file_server/pages/terminal_details_page.dart';
import '../../features/local_file_server/pages/shared_file_manager_page.dart';
import '../../features/workbench/presentation/workbench_page.dart';
import '../../features/session/presentation/login_devices_page.dart';
import '../../features/chat/presentation/chat_page.dart';
import '../../features/chat_settings/presentation/chat_settings_page.dart';
import '../../features/chat_settings/presentation/group_name_page.dart';
import '../../features/chat_settings/presentation/member_list_page.dart';
import '../../features/group_management/presentation/group_management_page.dart';
import '../../features/account/presentation/account_profile_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/settings/presentation/theme_settings_page.dart';
import '../../features/search/presentation/search_page.dart';
import '../../features/group/presentation/create_group_page.dart';
import '../../features/contact/presentation/add_friend_page.dart';
import '../../features/diagnostics/presentation/search_and_group_diagnostics_page.dart';
import '../app_navigation.dart';
import '../shell/application_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authNotifier = ref.watch(authControllerProvider.notifier);
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: authNotifier,
    redirect: (context, state) {
      final location = state.uri.path;
      final auth = ref.read(authControllerProvider);
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
      GoRoute(
        path: '/group-management/:sessionId',
        builder:
            (context, state) => GroupManagementPage(
              sessionId: state.pathParameters['sessionId']!,
            ),
      ),
      GoRoute(
        path: '/local-file-server',
        builder: (context, state) => const LocalFileServerPage(),
      ),
      GoRoute(
        path: '/local-file-server/files',
        builder: (context, state) => const SharedFileManagerPage(),
      ),
      GoRoute(
        path: '/local-file-server/terminal/:terminalId',
        builder:
            (context, state) => TerminalDetailsPage(
              terminalId: state.pathParameters['terminalId']!,
            ),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(path: '/search', builder: (context, state) => const SearchPage()),
      GoRoute(
        path: '/create-group',
        builder: (context, state) => const CreateGroupPage(),
      ),
      GoRoute(
        path: '/add-friend',
        builder:
            (context, state) => AddFriendPage(
              initialKeyword: state.uri.queryParameters['keyword'],
            ),
      ),
      GoRoute(
        path: '/diagnostics/search-and-group',
        builder: (context, state) => const SearchAndGroupDiagnosticsPage(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: '/settings/theme',
        builder: (context, state) => const ThemeSettingsPage(),
      ),
      GoRoute(
        path: '/settings/avatar',
        builder: (context, state) => const AvatarSettingsPage(),
      ),
      GoRoute(
        path: '/mine/account',
        builder: (context, state) => const AccountManagementPage(),
      ),
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
        path: '/diagnostics/remote-devtools',
        builder: (context, state) => const RemoteDevToolsDiagnosticsPage(),
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
        path: '/diagnostics/abp-configuration',
        builder: (context, state) => const AbpConfigurationDiagnosticsPage(),
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
      GoRoute(
        path: '/diagnostics/capabilities',
        builder: (context, state) => const ClientCapabilitiesDiagnosticsPage(),
      ),
      GoRoute(
        path: '/diagnostics/js-bridge',
        builder: (context, state) => const JsBridgeDiagnosticsPage(),
      ),
      GoRoute(
        path: '/diagnostics/media',
        builder: (context, state) => const MediaDiagnosticsPage(),
      ),
      GoRoute(
        path: '/diagnostics/media-preview',
        builder: (context, state) => const MediaPreviewDiagnosticsPage(),
      ),
      GoRoute(
        path: '/diagnostics/floating-window',
        builder: (context, state) => const FloatingWindowDiagnosticsPage(),
      ),
      GoRoute(
        path: '/diagnostics/webview-session',
        builder: (context, state) => const WebViewSessionDiagnosticsPage(),
      ),
      GoRoute(
        path: '/diagnostics/database',
        builder: (context, state) => const DatabaseDiagnosticsPage(),
      ),
      GoRoute(
        path: '/diagnostics/session-list',
        builder: (context, state) => const SessionListDiagnosticsPage(),
      ),
      GoRoute(
        path: '/diagnostics/chat',
        builder: (context, state) => const ChatDiagnosticsPage(),
      ),
      GoRoute(
        path: '/diagnostics/chat-bubble',
        builder: (context, state) => const ChatBubbleDiagnosticsPage(),
      ),
      GoRoute(
        path: '/diagnostics/js-bridge-harness',
        builder: (context, state) => const JsBridgeHarnessPage(),
      ),
      GoRoute(
        path: '/diagnostics/app-task',
        builder: (context, state) => const AppTaskDiagnosticsPage(),
      ),
      GoRoute(
        path: '/diagnostics/deep-link',
        builder: (context, state) => const DeepLinkDiagnosticsPage(),
      ),
      GoRoute(
        path: '/diagnostics/local-file-server',
        builder: (context, state) => const LocalFileServerPage(),
      ),
      GoRoute(
        path: '/diagnostics/native',
        builder: (context, state) => const NativeDiagnosticsPage(),
      ),
      GoRoute(
        path: '/diagnostics/device-registration',
        builder: (context, state) => const DeviceRegistrationDiagnosticsPage(),
      ),
      GoRoute(
        path: '/diagnostics/theme',
        builder: (context, state) => const ThemeDiagnosticsPage(),
      ),
      GoRoute(
        path: '/diagnostics/adaptive-page',
        builder: (context, state) => const AdaptivePageDiagnosticsPage(),
      ),
      GoRoute(
        path: '/diagnostics/half-page-sheet',
        builder: (context, state) => const HalfPageSheetDiagnosticsPage(),
      ),
      GoRoute(
        path: '/diagnostics/toast',
        builder: (context, state) => const ToastDiagnosticsPage(),
      ),
      GoRoute(
        path: '/diagnostics/modal',
        builder: (context, state) => const ModalDiagnosticsPage(),
      ),
      GoRoute(
        path: '/diagnostics/target-picker',
        builder: (context, state) => const TargetPickerDiagnosticsPage(),
      ),
      GoRoute(
        path: '/diagnostics/workbench-layout',
        builder: (context, state) => const WorkbenchLayoutDiagnosticsPage(),
      ),
      GoRoute(
        path: '/workbench',
        builder: (context, state) => const WorkbenchPage(),
      ),
      GoRoute(
        path: '/devices',
        builder: (context, state) => const LoginDevicesPage(),
      ),
      GoRoute(
        path: '/online-devices',
        builder: (context, state) => const LoginDevicesPage(onlineOnly: true),
      ),
      GoRoute(
        path: '/account/profile',
        builder: (context, state) => const AccountProfilePage(),
      ),
      GoRoute(
        path: '/group-name/:sessionUnitId',
        builder:
            (context, state) => GroupNamePage(
              ownerId:
                  int.tryParse(state.uri.queryParameters['ownerId'] ?? '') ?? 0,
              sessionUnitId: state.pathParameters['sessionUnitId']!,
              initialTitle: state.uri.queryParameters['title'],
            ),
      ),
      GoRoute(
        path: '/chat/:sessionUnitId/group-name',
        builder:
            (context, state) => GroupNamePage(
              ownerId:
                  int.tryParse(state.uri.queryParameters['ownerId'] ?? '') ?? 0,
              sessionUnitId: state.pathParameters['sessionUnitId']!,
              initialTitle: state.uri.queryParameters['title'],
            ),
      ),
      GoRoute(
        path: '/chat/:sessionUnitId/settings',
        builder:
            (context, state) => ChatSettingsPage(
              ownerId:
                  int.tryParse(state.uri.queryParameters['ownerId'] ?? '') ?? 0,
              sessionUnitId: state.pathParameters['sessionUnitId']!,
            ),
      ),
      GoRoute(
        path: '/chat/:sessionUnitId/members',
        builder:
            (context, state) => MemberListPage(
              ownerId:
                  int.tryParse(state.uri.queryParameters['ownerId'] ?? '') ?? 0,
              sessionUnitId: state.pathParameters['sessionUnitId']!,
            ),
      ),
      GoRoute(
        path: '/chat/:sessionUnitId',
        builder:
            (context, state) => ChatPage(
              ownerId:
                  int.tryParse(state.uri.queryParameters['ownerId'] ?? '') ?? 0,
              sessionUnitId: state.pathParameters['sessionUnitId']!,
              title: state.uri.queryParameters['title'] ?? '聊天',
            ),
      ),
    ],
  );
});
