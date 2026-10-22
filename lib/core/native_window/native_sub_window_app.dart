import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_navigation.dart';
import '../config/app_environment.dart';
import '../theme/app_theme.dart';
import '../platform/platform_facade.dart';
import '../platform/windows/windows_window_adapter.dart';
import '../browser/desktop_browser_window.dart';
import '../media/media_preview.dart';
import '../../features/diagnostics/presentation/abp_configuration_diagnostics_page.dart';
import '../../features/diagnostics/presentation/app_statistic_diagnostics_page.dart';
import '../../features/diagnostics/presentation/article_message_diagnostics_page.dart';
import '../../features/diagnostics/presentation/auth_diagnostics_page.dart';
import '../../features/diagnostics/presentation/chat_bubble_diagnostics_page.dart';
import '../../features/chat/presentation/widgets/desktop_screen_capture_view.dart';
import '../../features/diagnostics/presentation/chat_diagnostics_page.dart';
import '../../features/diagnostics/presentation/connection_test_page.dart';
import '../../features/diagnostics/presentation/database_diagnostics_page.dart';
import '../../features/diagnostics/presentation/desktop_windows_diagnostics_page.dart';
import '../../features/diagnostics/presentation/diagnostics_home_page.dart';
import '../../features/diagnostics/presentation/local_notification_diagnostics_page.dart';
import '../../features/diagnostics/presentation/privacy_and_update_diagnostics_page.dart';
import '../../features/diagnostics/presentation/remote_devtools_diagnostics_page.dart';
import '../../features/diagnostics/presentation/search_and_group_diagnostics_page.dart';
import '../../features/diagnostics/presentation/session_list_diagnostics_page.dart';
import '../../features/diagnostics/presentation/signalr_diagnostics_page.dart';
import '../../features/local_file_server/pages/local_file_server_page.dart';
import '../../features/local_file_server/pages/shared_file_manager_page.dart';
import '../../features/media/presentation/desktop_media_viewer_window.dart';
import '../../features/settings/presentation/desktop_settings_window.dart';
import '../../features/user/data/models/profile_subject.dart';
import 'desktop_profile_card_view.dart';
import 'desktop_sub_window_chat_view.dart';
import 'desktop_window_title_bar.dart';
import 'native_window_payload.dart';
import '../services/window_service.dart';
import '../services/tray_grouped_unread_provider.dart';
import '../services/tray_message_models.dart';
import '../services/tray_service.dart';
import '../widgets/desktop_tray_message_box.dart';
import '../widgets/desktop_startup_scene.dart';

/// 桌面端原生子窗口独立轻量入口
///
/// 严格遵循多引擎架构准则：
/// 1. 不执行全局 bootstrap（不重复注册设备、不重复创建 SignalR、不执行 DB migration）；
/// 2. 仅初始化渲染所需的最小绑定、基础主题与当前独立视窗；
/// 3. 通过 WindowMethodChannel 与主引擎进行双向 IPC 通信。
Future<void> runNativeSubWindowApp(List<String> args) async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  if (WindowsWindowAdapter.isWindows) {
    runApp(const DesktopStartupScene());
    await binding.endOfFrame;
  }

  WindowController? controller;
  try {
    controller = await WindowController.fromCurrentEngine();
  } catch (_) {}

  final payloadRaw = args.length > 2 ? args[2] : (controller?.arguments ?? '');
  final payload =
      NativeWindowPayload.tryParse(payloadRaw) ??
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

  final container = ProviderContainer(
    overrides: [
      appEnvironmentProvider.overrideWithValue(environment),
      trayServiceProvider.overrideWithValue(const SubWindowTrayService()),
      platformFacadeProvider.overrideWithValue(platformFacade),
      windowServiceProvider.overrideWith(
        (ref) => DefaultWindowService(
          platformFacade: platformFacade,
          isSubWindow: true,
        ),
      ),
    ],
  );
  rootProviderContainer ??= container;

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: NativeSubWindowApp(controller: controller, payload: payload),
    ),
  );
}

class NativeSubWindowApp extends ConsumerStatefulWidget {
  const NativeSubWindowApp({required this.payload, this.controller, super.key});

  final NativeWindowPayload payload;
  final WindowController? controller;

  @override
  ConsumerState<NativeSubWindowApp> createState() => _NativeSubWindowAppState();
}

class _NativeSubWindowAppState extends ConsumerState<NativeSubWindowApp> {
  bool _visible = true;
  Future<void>? _closing;
  late final WindowMethodChannel _mainIpcChannel;
  ThemeMode _themeMode = ThemeMode.dark;
  late NativeWindowPayload _currentPayload;
  Future<dynamic> Function(MethodCall call)? _childMethodHandler;

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
      GoRoute(path: '/', redirect: (_, _) => '/diagnostics'),
    ],
  );

  late final GoRouter _fileServerRouter = GoRouter(
    initialLocation: '/local-file-server',
    routes: [
      GoRoute(
        path: '/local-file-server',
        builder: (context, state) => const LocalFileServerPage(),
        routes: [
          GoRoute(
            path: 'files',
            builder: (context, state) => const SharedFileManagerPage(),
          ),
        ],
      ),
      GoRoute(path: '/', redirect: (_, _) => '/local-file-server'),
    ],
  );

  Widget _buildDiagnosticSubPage(String section) {
    switch (section) {
      case 'desktop-windows':
        return const DesktopWindowsDiagnosticsPage();
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WindowsWindowAdapter.setupCustomTitleBar();
      _refreshTraySnapshot();
      if (_currentPayload.type == SubWindowType.tray ||
          _currentPayload.type == SubWindowType.profileCard ||
          _currentPayload.type == SubWindowType.screenCapture) {
        // Flyout/tool sub-windows must remain hidden on launch until explicitly triggered
        // and must never show on the Windows taskbar.
        WindowsWindowAdapter.setToolWindow(true);
        WindowsWindowAdapter.hide();
      } else if (_currentPayload.type == SubWindowType.settings) {
        // Modal sub-window disabling parent window (Electron-style parent/modal)
        WindowsWindowAdapter.setModal(true);
      } else {
        // Ensure all other new sub-windows are centered on screen with responsive sizes
        switch (_currentPayload.type) {
          case SubWindowType.chat:
            WindowsWindowAdapter.center(width: 880, height: 640);
            break;
          case SubWindowType.diagnostics:
            WindowsWindowAdapter.center(width: 960, height: 700);
            break;
          case SubWindowType.localFileServer:
            WindowsWindowAdapter.center(width: 860, height: 620);
            break;
          case SubWindowType.browser:
            final initW =
                (widget.payload.extra?['initialWidth'] as num?)?.toInt() ??
                1024;
            final initH =
                (widget.payload.extra?['initialHeight'] as num?)?.toInt() ??
                720;
            WindowsWindowAdapter.center(width: initW, height: initH);
            break;
          case SubWindowType.media:
            WindowsWindowAdapter.center(width: 960, height: 700);
            break;
          default:
            WindowsWindowAdapter.center();
            break;
        }
      }
    });
    WindowsWindowAdapter.onCloseRequested = _handleClose;
    _currentPayload = widget.payload;
    final initialThemeStr = widget.payload.extra?['themeMode'] as String?;
    if (initialThemeStr != null) {
      _themeMode = ThemeMode.values.firstWhere(
        (e) => e.name == initialThemeStr,
        orElse: () => ThemeMode.system,
      );
    } else {
      _themeMode = ThemeMode.system;
    }

    _mainIpcChannel = const WindowMethodChannel(
      'gotoim/ipc_to_main',
      mode: ChannelMode.unidirectional,
    );

    widget.controller?.setWindowMethodHandler((call) async {
      switch (call.method) {
        case 'theme_changed':
          final args = call.arguments as Map?;
          final modeStr = args?['themeMode'] as String?;
          if (modeStr != null) {
            final target = ThemeMode.values.firstWhere(
              (e) => e.name == modeStr,
              orElse: () => ThemeMode.system,
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
              _visible = true;
              _currentPayload = NativeWindowPayload.fromMap(
                Map<String, dynamic>.from(map),
              );
              final themeStr = _currentPayload.extra?['themeMode'] as String?;
              if (themeStr != null) {
                _themeMode = ThemeMode.values.firstWhere(
                  (e) => e.name == themeStr,
                  orElse: () => _themeMode,
                );
              }
            });
          }
          return true;
        case 'tray_update':
          if (call.arguments is Map) {
            ref
                .read(trayGroupedUnreadProvider.notifier)
                .applySnapshot(
                  TrayGroupedUnreadState.fromJson(call.arguments as Map),
                );
          }
          return true;
        case 'disposeWindow':
          await WindowsWindowAdapter.destroy();
          return true;
        case 'bringToFront':
          if (mounted) setState(() => _visible = true);
          await widget.controller?.show();
          if (_currentPayload.type == SubWindowType.tray) {
            await _refreshTraySnapshot();
            await WindowsWindowAdapter.showTrayFlyout();
          } else {
            await WindowsWindowAdapter.bringToFront();
          }
          if (_childMethodHandler != null) {
            await _childMethodHandler!(call);
          }
          return true;
        case 'position_flyout':
          if (call.arguments is Map) {
            final map = call.arguments as Map;
            final x = (map['x'] as num?)?.toInt() ?? 0;
            final y = (map['y'] as num?)?.toInt() ?? 0;
            final w = (map['width'] as num?)?.toInt() ?? 380;
            final h = (map['height'] as num?)?.toInt() ?? 420;
            final noActivate = map['noActivate'] != false;
            await WindowsWindowAdapter.positionFlyout(
              x: x,
              y: y,
              width: w,
              height: h,
              noActivate: noActivate,
            );
          }
          return true;
        case 'account_logout':
          await _handleLogout(notifyMain: false);
          return true;
        case 'hide_profile':
          await WindowsWindowAdapter.hide();
          if (_childMethodHandler != null) {
            await _childMethodHandler!(call);
          }
          return true;
        case 'show_screen_capture':
          if (_childMethodHandler != null) {
            await _childMethodHandler!(call);
          }
          return true;
        case 'hide_screen_capture':
          await WindowsWindowAdapter.hide();
          return true;
        case 'dock_to_parent':
          final dockArgs = call.arguments as Map?;
          debugPrint(
            '[BrowserDock SubWindow] received dock_to_parent: args=$dockArgs',
          );
          if (dockArgs != null) {
            final x = (dockArgs['x'] as num?)?.toInt() ?? 0;
            final y = (dockArgs['y'] as num?)?.toInt() ?? 0;
            final w = (dockArgs['width'] as num?)?.toInt() ?? 400;
            final h = (dockArgs['height'] as num?)?.toInt() ?? 600;
            final success = await WindowsWindowAdapter.dockToParent(
              x: x,
              y: y,
              width: w,
              height: h,
            );
            debugPrint(
              '[BrowserDock SubWindow] dockToParent native result=$success',
            );
            if (success) {
              if (mounted) {
                setState(() => _visible = true);
              }
              if (_childMethodHandler != null) {
                await _childMethodHandler!(
                  const MethodCall('set_dock_mode', true),
                );
              }
            }
            return success;
          }
          return false;
        case 'update_docked_bounds':
          final boundsArgs = call.arguments as Map?;
          if (boundsArgs != null) {
            final x = (boundsArgs['x'] as num?)?.toInt() ?? 0;
            final y = (boundsArgs['y'] as num?)?.toInt() ?? 0;
            final w = (boundsArgs['width'] as num?)?.toInt() ?? 400;
            final h = (boundsArgs['height'] as num?)?.toInt() ?? 600;
            debugPrint(
              '[BrowserDock SubWindow] update_docked_bounds: ($x, $y, $w, $h)',
            );
            return await WindowsWindowAdapter.updateDockedBounds(
              x: x,
              y: y,
              width: w,
              height: h,
            );
          }
          return false;
        case 'undock_from_parent':
          debugPrint('[BrowserDock SubWindow] received undock_from_parent');
          final args = call.arguments as Map?;
          final showWindow = args?['showWindow'] as bool? ?? true;
          final success = await WindowsWindowAdapter.undockFromParent(
            showWindow: showWindow,
          );
          debugPrint(
            '[BrowserDock SubWindow] undockFromParent native result=$success',
          );
          if (success) {
            if (_childMethodHandler != null) {
              await _childMethodHandler!(
                const MethodCall('set_dock_mode', false),
              );
            }
          }
          return success;
        case 'tray_flyout':
          await _refreshTraySnapshot();
          await WindowsWindowAdapter.showTrayFlyout();
          return true;
        case 'setModal':
          final enable = call.arguments != false;
          await WindowsWindowAdapter.setModal(enable);
          return true;
        case 'center':
          final args = call.arguments as Map?;
          final w = args?['width'] as int?;
          final h = args?['height'] as int?;
          await WindowsWindowAdapter.center(width: w, height: h);
          return true;
        case 'close':
          await _handleClose();
          return true;
        default:
          if (_childMethodHandler != null) {
            return await _childMethodHandler!(call);
          }
          return null;
      }
    });
  }

  Future<void> _refreshTraySnapshot() async {
    try {
      final raw = await _mainIpcChannel.invokeMethod('tray_snapshot');
      if (mounted && raw is Map) {
        ref
            .read(trayGroupedUnreadProvider.notifier)
            .applySnapshot(TrayGroupedUnreadState.fromJson(raw));
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    WindowsWindowAdapter.onCloseRequested = null;
    _diagnosticRouter.dispose();
    _fileServerRouter.dispose();
    super.dispose();
  }

  Future<void> _handleClose() =>
      _closing ??= _closeOnce().whenComplete(() {
        _closing = null;
      });

  Future<void> _closeOnce() async {
    if (mounted && _currentPayload.type == SubWindowType.media) {
      setState(() => _visible = false);
    }
    if (_currentPayload.type == SubWindowType.settings) {
      await WindowsWindowAdapter.setModal(false);
    }
    try {
      await _mainIpcChannel.invokeMethod('sub_window_closed', {
        'targetId': _currentPayload.targetId,
        'windowId': widget.controller?.windowId,
      });
      // Main owns hiding and caching. A second hide here can race with a
      // rapid reopen and hide the newly restored window.
      return;
    } catch (_) {}
    if (widget.controller != null) {
      await widget.controller!.hide();
    }
  }

  Future<void> _handleLogout({bool notifyMain = true}) async {
    if (notifyMain) {
      try {
        await _mainIpcChannel.invokeMethod('app_logout');
      } catch (_) {}
    }
    await _handleClose();
  }

  @override
  Widget build(BuildContext context) {
    final lightTheme = AppTheme.lightTheme();
    final darkTheme = AppTheme.darkTheme();

    if (_currentPayload.type == SubWindowType.diagnostics) {
      return MaterialApp.router(
        title: _currentPayload.title,
        debugShowCheckedModeBanner: false,
        themeMode: _themeMode,
        theme: lightTheme,
        darkTheme: darkTheme,
        builder: _buildToolFrame,
        routerConfig: _diagnosticRouter,
      );
    }

    if (_currentPayload.type == SubWindowType.localFileServer) {
      return MaterialApp.router(
        title: _currentPayload.title,
        debugShowCheckedModeBanner: false,
        themeMode: _themeMode,
        theme: lightTheme,
        darkTheme: darkTheme,
        builder: _buildToolFrame,
        routerConfig: _fileServerRouter,
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

  Widget _buildToolFrame(BuildContext context, Widget? child) =>
      DesktopToolWindowFrame(
        title: _currentPayload.title,
        onClose: _handleClose,
        child: child ?? const SizedBox.shrink(),
      );

  Widget _buildSubWindowContent() {
    if (!_visible) return const SizedBox.shrink();
    switch (_currentPayload.type) {
      case SubWindowType.profileCard:
        final rawMember = _currentPayload.extra?['profileSubject'];
        final initialSubject =
            rawMember is Map
                ? ProfileSubject.fromMap(Map<String, dynamic>.from(rawMember))
                : null;
        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          body: DesktopProfileCardView(
            initialSubject: initialSubject,
            onClose: _handleClose,
            onRegisterMethodHandler: (handler) {
              _childMethodHandler = handler;
            },
          ),
        );
      case SubWindowType.tray:
        return const Scaffold(body: DesktopTrayMessageBox(nativeWindow: true));
      case SubWindowType.screenCapture:
        return DesktopScreenCaptureView(
          onClose: _handleClose,
          onRegisterMethodHandler: (handler) {
            _childMethodHandler = handler;
          },
        );
      case SubWindowType.settings:
        return DesktopSettingsWindow(
          isSubWindow: true,
          extra: _currentPayload.extra,
          onClose: _handleClose,
          onLogout: _handleLogout,
        );

      case SubWindowType.browser:
        return DesktopBrowserWindow(
          key: const ValueKey('desktop_browser_window'),
          initialUrl: _currentPayload.url ?? 'https://www.bing.com',
          title: _currentPayload.title,
          fallbackContent: _currentPayload.fallbackContent,
          isSubWindow: true,
          onClose: _handleClose,
          onRegisterMethodHandler: (handler) {
            _childMethodHandler = handler;
          },
        );

      case SubWindowType.media:
        final rawItems = _currentPayload.mediaItems;
        final items =
            rawItems != null && rawItems.isNotEmpty
                ? rawItems.map((map) {
                  final source = map['source'] as String? ?? '';
                  final typeStr = map['type'] as String?;
                  final isVideo =
                      typeStr == 'video' ||
                      (typeStr == null &&
                          (source.toLowerCase().endsWith('.mp4') ||
                              source.toLowerCase().endsWith('.mov')));
                  final localPath = map['localPath'] as String?;
                  return MediaPreviewItem(
                    id: map['id'] as String? ?? source,
                    messageId: map['messageId'] as String? ?? 'media',
                    type:
                        isVideo
                            ? MediaPreviewType.video
                            : MediaPreviewType.image,
                    source: source,
                    localPath: localPath,
                    userId: map['userId'] as String?,
                    chatTarget: map['chatTarget'] as String?,
                    createdAt: DateTime.tryParse(
                      map['createdAt']?.toString() ?? '',
                    ),
                    fileName: map['fileName'] as String?,
                    thumbnail: map['thumbnail'] as String?,
                    heroTag: 'media-$source',
                  );
                }).toList()
                : [
                  MediaPreviewItem(
                    id: _currentPayload.url ?? 'media',
                    messageId: 'media',
                    type:
                        (_currentPayload.url?.toLowerCase().endsWith('.mp4') ??
                                false)
                            ? MediaPreviewType.video
                            : MediaPreviewType.image,
                    source: _currentPayload.url ?? '',
                    heroTag: 'media-${_currentPayload.url}',
                  ),
                ];
        return DesktopMediaViewerWindow(
          key: ValueKey(
            'media_${_currentPayload.url}_${_currentPayload.initialIndex}_${items.length}',
          ),
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
            onRegisterHandler: (handler) => _childMethodHandler = handler,
          );
        }
        return Scaffold(
          body: Center(child: Text('独立聊天窗口：${_currentPayload.title}')),
        );

      case SubWindowType.diagnostics:
        return const DiagnosticsHomePage();

      case SubWindowType.localFileServer:
        return const LocalFileServerPage();
    }
  }
}
