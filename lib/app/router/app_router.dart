import 'package:flutter/material.dart';
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
import '../../features/settings/presentation/message_alert_settings_page.dart';
import '../../features/search/presentation/search_page.dart';
import '../../features/group/presentation/create_group_page.dart';
import '../../features/contact/presentation/add_friend_page.dart';
import '../../features/diagnostics/presentation/search_and_group_diagnostics_page.dart';
import '../../features/diagnostics/presentation/privacy_and_update_diagnostics_page.dart';
import '../../features/diagnostics/presentation/badge_diagnostics_page.dart';
import '../app_navigation.dart';
import '../shell/application_shell.dart';
import 'route_transitions.dart';

GoRoute _buildAppRoute({
  required String path,
  required Widget Function(BuildContext context, GoRouterState state) builder,
  bool isModal = false,
  bool isFade = false,
}) {
  return GoRoute(
    path: path,
    pageBuilder: (context, state) {
      final child = builder(context, state);
      if (isModal) {
        return AppRouteTransition.slideUp(
          context: context,
          state: state,
          child: child,
        );
      }
      if (isFade) {
        return AppRouteTransition.fade(
          context: context,
          state: state,
          child: child,
        );
      }
      return AppRouteTransition.slideRight(
        context: context,
        state: state,
        child: child,
      );
    },
  );
}

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
      _buildAppRoute(
        path: '/',
        isFade: true,
        builder: (context, state) => const ApplicationShell(),
      ),
      _buildAppRoute(
        path: '/group-management/:sessionId',
        builder:
            (context, state) => GroupManagementPage(
              sessionId: state.pathParameters['sessionId']!,
            ),
      ),
      _buildAppRoute(
        path: '/local-file-server',
        builder: (context, state) => const LocalFileServerPage(),
      ),
      _buildAppRoute(
        path: '/local-file-server/files',
        builder: (context, state) => const SharedFileManagerPage(),
      ),
      _buildAppRoute(
        path: '/local-file-server/terminal/:terminalId',
        builder:
            (context, state) => TerminalDetailsPage(
              terminalId: state.pathParameters['terminalId']!,
            ),
      ),
      _buildAppRoute(
        path: '/login',
        isFade: true,
        builder: (context, state) => const LoginPage(),
      ),
      _buildAppRoute(
        path: '/search',
        builder: (context, state) => const SearchPage(),
      ),
      _buildAppRoute(
        path: '/create-group',
        builder: (context, state) => const CreateGroupPage(),
      ),
      _buildAppRoute(
        path: '/add-friend',
        builder:
            (context, state) => AddFriendPage(
              initialKeyword: state.uri.queryParameters['keyword'],
            ),
      ),
      _buildAppRoute(
        path: '/diagnostics/search-and-group',
        builder: (context, state) => const SearchAndGroupDiagnosticsPage(),
      ),
      _buildAppRoute(
        path: '/settings',
        builder: (context, state) => const SettingsPage(),
      ),
      _buildAppRoute(
        path: '/settings/theme',
        builder: (context, state) => const ThemeSettingsPage(),
      ),
      _buildAppRoute(
        path: '/chat/:sessionUnitId/notifications',
        builder: (context, state) => MessageAlertSettingsPage(
          sessionUnitId: state.pathParameters['sessionUnitId']!,
          title: state.uri.queryParameters['title'] ?? '聊天',
        ),
      ),
      _buildAppRoute(
        path: '/settings/avatar',
        builder: (context, state) => const AvatarSettingsPage(),
      ),
      _buildAppRoute(
        path: '/mine/account',
        builder: (context, state) => const AccountManagementPage(),
      ),
      _buildAppRoute(
        path: '/scan-login',
        isModal: true,
        builder: (context, state) {
          final scanText = state.uri.queryParameters['scanText'] ?? '';
          return ScanLoginConfirmationPage(scanText: scanText);
        },
      ),
      _buildAppRoute(
        path: '/scan-login/scan',
        isModal: true,
        builder: (context, state) => const ScanLoginScanPage(),
      ),
      _buildAppRoute(
        path: '/splash',
        isFade: true,
        builder: (context, state) => const AuthLoadingPage(),
      ),
      _buildAppRoute(
        path: '/diagnostics',
        builder: (context, state) => const DiagnosticsHomePage(),
      ),
      _buildAppRoute(
        path: '/diagnostics/remote-devtools',
        builder: (context, state) => const RemoteDevToolsDiagnosticsPage(),
      ),
      _buildAppRoute(
        path: '/diagnostics/auth',
        builder: (context, state) => const AuthDiagnosticsPage(),
      ),
      _buildAppRoute(
        path: '/diagnostics/api',
        builder: (context, state) => const ConnectionTestPage(),
      ),
      _buildAppRoute(
        path: '/diagnostics/abp-configuration',
        builder: (context, state) => const AbpConfigurationDiagnosticsPage(),
      ),
      _buildAppRoute(
        path: '/diagnostics/signalr',
        builder: (context, state) => const SignalRDiagnosticsPage(),
      ),
      _buildAppRoute(
        path: '/diagnostics/notifications',
        builder: (context, state) => const LocalNotificationDiagnosticsPage(),
      ),
      _buildAppRoute(
        path: '/diagnostics/scan-code',
        builder: (context, state) => const ScanCodeDiagnosticsPage(),
      ),
      _buildAppRoute(
        path: '/diagnostics/capabilities',
        builder: (context, state) => const ClientCapabilitiesDiagnosticsPage(),
      ),
      _buildAppRoute(
        path: '/diagnostics/js-bridge',
        builder: (context, state) => const JsBridgeDiagnosticsPage(),
      ),
      _buildAppRoute(
        path: '/diagnostics/media',
        builder: (context, state) => const MediaDiagnosticsPage(),
      ),
      _buildAppRoute(
        path: '/diagnostics/media-preview',
        builder: (context, state) => const MediaPreviewDiagnosticsPage(),
      ),
      _buildAppRoute(
        path: '/diagnostics/floating-window',
        builder: (context, state) => const FloatingWindowDiagnosticsPage(),
      ),
      _buildAppRoute(
        path: '/diagnostics/webview-session',
        builder: (context, state) => const WebViewSessionDiagnosticsPage(),
      ),
      _buildAppRoute(
        path: '/diagnostics/database',
        builder: (context, state) => const DatabaseDiagnosticsPage(),
      ),
      _buildAppRoute(
        path: '/diagnostics/session-list',
        builder: (context, state) => const SessionListDiagnosticsPage(),
      ),
      _buildAppRoute(
        path: '/diagnostics/chat',
        builder: (context, state) => const ChatDiagnosticsPage(),
      ),
      _buildAppRoute(
        path: '/diagnostics/chat-bubble',
        builder: (context, state) => const ChatBubbleDiagnosticsPage(),
      ),
      _buildAppRoute(
        path: '/diagnostics/js-bridge-harness',
        builder: (context, state) => const JsBridgeHarnessPage(),
      ),
      _buildAppRoute(
        path: '/diagnostics/app-task',
        builder: (context, state) => const AppTaskDiagnosticsPage(),
      ),
      _buildAppRoute(
        path: '/diagnostics/deep-link',
        builder: (context, state) => const DeepLinkDiagnosticsPage(),
      ),
      _buildAppRoute(
        path: '/diagnostics/local-file-server',
        builder: (context, state) => const LocalFileServerPage(),
      ),
      _buildAppRoute(
        path: '/diagnostics/native',
        builder: (context, state) => const NativeDiagnosticsPage(),
      ),
      _buildAppRoute(
        path: '/diagnostics/device-registration',
        builder: (context, state) => const DeviceRegistrationDiagnosticsPage(),
      ),
      _buildAppRoute(
        path: '/diagnostics/theme',
        builder: (context, state) => const ThemeDiagnosticsPage(),
      ),
      _buildAppRoute(
        path: '/diagnostics/adaptive-page',
        builder: (context, state) => const AdaptivePageDiagnosticsPage(),
      ),
      _buildAppRoute(
        path: '/diagnostics/half-page-sheet',
        builder: (context, state) => const HalfPageSheetDiagnosticsPage(),
      ),
      _buildAppRoute(
        path: '/diagnostics/toast',
        builder: (context, state) => const ToastDiagnosticsPage(),
      ),
      _buildAppRoute(
        path: '/diagnostics/modal',
        builder: (context, state) => const ModalDiagnosticsPage(),
      ),
      _buildAppRoute(
        path: '/diagnostics/target-picker',
        builder: (context, state) => const TargetPickerDiagnosticsPage(),
      ),
      _buildAppRoute(
        path: '/diagnostics/workbench-layout',
        builder: (context, state) => const WorkbenchLayoutDiagnosticsPage(),
      ),
      _buildAppRoute(
        path: '/diagnostics/privacy-and-update',
        builder: (context, state) => const PrivacyAndUpdateDiagnosticsPage(),
      ),
      _buildAppRoute(
        path: '/diagnostics/badge',
        builder: (context, state) => const BadgeDiagnosticsPage(),
      ),
      _buildAppRoute(
        path: '/workbench',
        builder: (context, state) => const WorkbenchPage(),
      ),
      _buildAppRoute(
        path: '/devices',
        builder: (context, state) => const LoginDevicesPage(),
      ),
      _buildAppRoute(
        path: '/online-devices',
        builder: (context, state) => const LoginDevicesPage(onlineOnly: true),
      ),
      _buildAppRoute(
        path: '/account/profile',
        builder: (context, state) => const AccountProfilePage(),
      ),
      _buildAppRoute(
        path: '/group-name/:sessionUnitId',
        builder:
            (context, state) => GroupNamePage(
              ownerId:
                  int.tryParse(state.uri.queryParameters['ownerId'] ?? '') ?? 0,
              sessionUnitId: state.pathParameters['sessionUnitId']!,
              initialTitle: state.uri.queryParameters['title'],
            ),
      ),
      _buildAppRoute(
        path: '/chat/:sessionUnitId/group-name',
        builder:
            (context, state) => GroupNamePage(
              ownerId:
                  int.tryParse(state.uri.queryParameters['ownerId'] ?? '') ?? 0,
              sessionUnitId: state.pathParameters['sessionUnitId']!,
              initialTitle: state.uri.queryParameters['title'],
            ),
      ),
      _buildAppRoute(
        path: '/chat/:sessionUnitId/settings',
        builder:
            (context, state) => ChatSettingsPage(
              ownerId:
                  int.tryParse(state.uri.queryParameters['ownerId'] ?? '') ?? 0,
              sessionUnitId: state.pathParameters['sessionUnitId']!,
            ),
      ),
      _buildAppRoute(
        path: '/chat/:sessionUnitId/members',
        builder:
            (context, state) => MemberListPage(
              ownerId:
                  int.tryParse(state.uri.queryParameters['ownerId'] ?? '') ?? 0,
              sessionUnitId: state.pathParameters['sessionUnitId']!,
            ),
      ),
      _buildAppRoute(
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
