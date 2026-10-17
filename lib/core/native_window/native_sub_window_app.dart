import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/app_environment.dart';
import '../platform/platform_facade.dart';
import '../browser/desktop_browser_window.dart';
import '../media/media_preview.dart';
import '../../features/diagnostics/presentation/abp_configuration_diagnostics_page.dart';
import '../../features/diagnostics/presentation/app_statistic_diagnostics_page.dart';
import '../../features/diagnostics/presentation/article_message_diagnostics_page.dart';
import '../../features/diagnostics/presentation/auth_diagnostics_page.dart';
import '../../features/diagnostics/presentation/chat_bubble_diagnostics_page.dart';
import '../../features/diagnostics/presentation/chat_diagnostics_page.dart';
import '../../features/diagnostics/presentation/connection_test_page.dart';
import '../../features/diagnostics/presentation/database_diagnostics_page.dart';
import '../../features/diagnostics/presentation/diagnostics_home_page.dart';
import '../../features/diagnostics/presentation/local_notification_diagnostics_page.dart';
import '../../features/diagnostics/presentation/privacy_and_update_diagnostics_page.dart';
import '../../features/diagnostics/presentation/remote_devtools_diagnostics_page.dart';
import '../../features/diagnostics/presentation/search_and_group_diagnostics_page.dart';
import '../../features/diagnostics/presentation/session_list_diagnostics_page.dart';
import '../../features/diagnostics/presentation/signalr_diagnostics_page.dart';
import '../../features/local_file_server/pages/local_file_server_page.dart';
import '../../features/media/presentation/desktop_media_viewer_window.dart';
import '../../features/settings/presentation/desktop_settings_window.dart';
import 'desktop_sub_window_chat_view.dart';
import 'native_window_payload.dart';

/// 桌面端原生子窗口独立轻量入口
///
/// 严格遵循多引擎架构准则：
/// 1. 不执行全局 bootstrap（不重复注册设备、不重复创建 SignalR、不执行 DB migration）；
/// 2. 仅初始化渲染所需的最小绑定、基础主题与当前独立视窗；
/// 3. 通过 WindowMethodChannel 与主引擎进行双向 IPC 通信。
Future<void> runNativeSubWindowApp(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  WindowController? controller;
  try {
    controller = await WindowController.fromCurrentEngine();
  } catch (_) {}

  final payloadRaw = args.length > 2 ? args[2] : (controller?.arguments ?? '');
  final payload = NativeWindowPayload.tryParse(payloadRaw) ??
      const NativeWindowPayload(
        type: SubWindowType.settings,
        title: 'GotoIM',
        targetId: 'sub_window_fallback',
      );

  // 监听来自主窗口的 Method 调用
  if (controller != null) {
    controller.setWindowMethodHandler((call) async {
      switch (call.method) {
        case 'bringToFront':
          await controller?.show();
          return true;
        case 'close':
          await controller?.hide();
          return true;
        default:
          return null;
      }
    });
  }

  // 加载轻量环境与主题，提供最小 ProviderScope 覆盖
  const flavorName = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );
  final flavor = AppEnvironment.parseFlavor(flavorName);
  try {
    await dotenv.load(fileName: '.env.${flavor.name}');
  } catch (_) {
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {}
  }
  final environment = AppEnvironment.fromDotEnv(flavor);
  final platformFacade = createPlatformFacade();

  runApp(
    ProviderScope(
      overrides: [
        appEnvironmentProvider.overrideWithValue(environment),
        platformFacadeProvider.overrideWithValue(platformFacade),
      ],
      child: NativeSubWindowApp(
        controller: controller,
        payload: payload,
      ),
    ),
  );
}

class NativeSubWindowApp extends StatefulWidget {
  const NativeSubWindowApp({
    required this.payload,
    this.controller,
    super.key,
  });

  final NativeWindowPayload payload;
  final WindowController? controller;

  @override
  State<NativeSubWindowApp> createState() => _NativeSubWindowAppState();
}

class _NativeSubWindowAppState extends State<NativeSubWindowApp> {
  late final WindowMethodChannel _mainIpcChannel;
  ThemeMode _themeMode = ThemeMode.dark;
  late NativeWindowPayload _currentPayload;

  late final GoRouter _diagnosticRouter = GoRouter(
    initialLocation: '/diagnostics',
    routes: [
      GoRoute(
        path: '/diagnostics',
        builder: (context, state) => const DiagnosticsHomePage(),
        routes: [
          GoRoute(
            path: ':section',
            builder: (context, state) {
              final section = state.pathParameters['section'] ?? '';
              return _buildDiagnosticSubPage(section);
            },
          ),
        ],
      ),
      GoRoute(
        path: '/',
        redirect: (_, _) => '/diagnostics',
      ),
    ],
  );

  Widget _buildDiagnosticSubPage(String section) {
    switch (section) {
      case 'remote-devtools':
        return const RemoteDevToolsDiagnosticsPage();
      case 'auth':
        return const AuthDiagnosticsPage();
      case 'api':
        return const ConnectionTestPage();
      case 'abp-configuration':
        return const AbpConfigurationDiagnosticsPage();
      case 'signalr':
        return const SignalRDiagnosticsPage();
      case 'connection':
        return const ConnectionTestPage();
      case 'database':
        return const DatabaseDiagnosticsPage();
      case 'privacy-and-update':
        return const PrivacyAndUpdateDiagnosticsPage();
      case 'statistic':
        return const AppStatisticDiagnosticsPage();
      case 'article-message':
        return const ArticleMessageDiagnosticsPage();
      case 'session-list':
        return const SessionListDiagnosticsPage();
      case 'chat':
        return const ChatDiagnosticsPage();
      case 'chat-bubble':
        return const ChatBubbleDiagnosticsPage();
      case 'notifications':
        return const LocalNotificationDiagnosticsPage();
      case 'search-and-group':
        return const SearchAndGroupDiagnosticsPage();
      default:
        return Scaffold(
          appBar: AppBar(title: Text('诊断模块: $section')),
          body: Center(child: Text('诊断模块: $section')),
        );
    }
  }

  @override
  void initState() {
    super.initState();
    _currentPayload = widget.payload;
    final initialThemeStr = widget.payload.extra?['themeMode'] as String?;
    if (initialThemeStr != null) {
      _themeMode = ThemeMode.values.firstWhere(
        (e) => e.name == initialThemeStr,
        orElse: () => ThemeMode.dark,
      );
    }

    _mainIpcChannel = const WindowMethodChannel(
      'gotoim/ipc_to_main',
      mode: ChannelMode.bidirectional,
    );

    widget.controller?.setWindowMethodHandler((call) async {
      switch (call.method) {
        case 'theme_changed':
          final args = call.arguments as Map?;
          final modeStr = args?['themeMode'] as String?;
          if (modeStr != null) {
            final target = ThemeMode.values.firstWhere(
              (e) => e.name == modeStr,
              orElse: () => ThemeMode.dark,
            );
            if (mounted) {
              setState(() => _themeMode = target);
            }
          }
          return true;
        case 'update_payload':
          final map = call.arguments as Map?;
          if (map != null && mounted) {
            setState(() {
              _currentPayload = NativeWindowPayload.fromMap(
                Map<String, dynamic>.from(map),
              );
            });
          }
          return true;
        case 'bringToFront':
          await widget.controller?.show();
          return true;
        case 'account_logout':
          await _handleLogout();
          return true;
        case 'close':
          await _handleClose();
          return true;
        default:
          return null;
      }
    });
  }

  Future<void> _handleClose() async {
    try {
      await _mainIpcChannel.invokeMethod('sub_window_closed', {
        'targetId': _currentPayload.targetId,
        'windowId': widget.controller?.windowId,
      });
    } catch (_) {}
    if (widget.controller != null) {
      await widget.controller!.hide();
    }
  }

  Future<void> _handleLogout() async {
    try {
      await _mainIpcChannel.invokeMethod('app_logout');
    } catch (_) {}
    await _handleClose();
  }

  @override
  Widget build(BuildContext context) {
    final lightTheme = ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: Colors.white,
      fontFamily: 'Segoe UI',
      useMaterial3: true,
    );
    final darkTheme = ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF1E1E1E),
      fontFamily: 'Segoe UI',
      useMaterial3: true,
    );

    if (_currentPayload.type == SubWindowType.diagnostics) {
      return MaterialApp.router(
        title: _currentPayload.title,
        debugShowCheckedModeBanner: false,
        themeMode: _themeMode,
        theme: lightTheme,
        darkTheme: darkTheme,
        routerConfig: _diagnosticRouter,
      );
    }

    return MaterialApp(
      title: _currentPayload.title,
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: lightTheme,
      darkTheme: darkTheme,
      home: _buildSubWindowContent(),
    );
  }

  Widget _buildSubWindowContent() {
    switch (_currentPayload.type) {
      case SubWindowType.settings:
        return DesktopSettingsWindow(
          isSubWindow: true,
          extra: _currentPayload.extra,
          onClose: _handleClose,
          onLogout: _handleLogout,
        );

      case SubWindowType.browser:
        return DesktopBrowserWindow(
          initialUrl: _currentPayload.url ?? 'https://www.bing.com',
          title: _currentPayload.title,
          fallbackContent: _currentPayload.fallbackContent,
          isSubWindow: true,
          onClose: _handleClose,
        );

      case SubWindowType.media:
        final rawItems = _currentPayload.mediaItems;
        final items = rawItems != null && rawItems.isNotEmpty
            ? rawItems.map((map) {
                final source = map['source'] as String? ?? '';
                final typeStr = map['type'] as String?;
                final isVideo = typeStr == 'video' ||
                    (typeStr == null &&
                        (source.toLowerCase().endsWith('.mp4') ||
                            source.toLowerCase().endsWith('.mov')));
                final localPath = map['localPath'] as String?;
                return MediaPreviewItem(
                  id: map['id'] as String? ?? source,
                  messageId: map['messageId'] as String? ?? 'media',
                  type: isVideo ? MediaPreviewType.video : MediaPreviewType.image,
                  source: source,
                  localPath: localPath,
                  heroTag: 'media-$source',
                );
              }).toList()
            : [
                MediaPreviewItem(
                  id: _currentPayload.url ?? 'media',
                  messageId: 'media',
                  type: (_currentPayload.url?.toLowerCase().endsWith('.mp4') ?? false)
                      ? MediaPreviewType.video
                      : MediaPreviewType.image,
                  source: _currentPayload.url ?? '',
                  heroTag: 'media-${_currentPayload.url}',
                ),
              ];
        return DesktopMediaViewerWindow(
          items: items,
          initialIndex: _currentPayload.initialIndex,
          isSubWindow: true,
          onClose: _handleClose,
        );

      case SubWindowType.chat:
        if (widget.controller != null) {
          return DesktopSubWindowChatView(
            payload: _currentPayload,
            controller: widget.controller!,
            onClose: _handleClose,
          );
        }
        return Scaffold(
          body: Center(
            child: Text('独立聊天窗口：${_currentPayload.title}'),
          ),
        );

      case SubWindowType.diagnostics:
        return const DiagnosticsHomePage();

      case SubWindowType.localFileServer:
        return const LocalFileServerPage();
    }
  }
}
