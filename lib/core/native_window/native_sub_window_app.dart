import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_environment.dart';
import '../platform/platform_facade.dart';
import '../browser/desktop_browser_window.dart';
import '../media/media_preview.dart';
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

  @override
  void initState() {
    super.initState();
    _mainIpcChannel = const WindowMethodChannel(
      'gotoim/ipc_to_main',
      mode: ChannelMode.unidirectional,
    );
  }

  Future<void> _handleClose() async {
    try {
      await _mainIpcChannel.invokeMethod('sub_window_closed', {
        'targetId': widget.payload.targetId,
        'windowId': widget.controller?.windowId,
      });
    } catch (_) {}
    if (widget.controller != null) {
      await widget.controller!.hide();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: widget.payload.title,
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark, // 桌面端原生子窗口默认使用深色优雅微信质感
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        fontFamily: 'Segoe UI',
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
        fontFamily: 'Segoe UI',
        useMaterial3: true,
      ),
      home: _buildSubWindowContent(),
    );
  }

  Widget _buildSubWindowContent() {
    switch (widget.payload.type) {
      case SubWindowType.settings:
        return DesktopSettingsWindow(
          isSubWindow: true,
          extra: widget.payload.extra,
          onClose: _handleClose,
        );

      case SubWindowType.browser:
        return DesktopBrowserWindow(
          initialUrl: widget.payload.url ?? 'https://www.bing.com',
          title: widget.payload.title,
          fallbackContent: widget.payload.fallbackContent,
          isSubWindow: true,
          onClose: _handleClose,
        );

      case SubWindowType.media:
        final rawItems = widget.payload.mediaItems;
        final items = rawItems != null && rawItems.isNotEmpty
            ? rawItems.map((map) {
                final source = map['source'] as String? ?? '';
                final isVideo = source.toLowerCase().endsWith('.mp4') ||
                    source.toLowerCase().endsWith('.mov');
                return MediaPreviewItem(
                  id: map['id'] as String? ?? source,
                  messageId: map['messageId'] as String? ?? 'media',
                  type: isVideo ? MediaPreviewType.video : MediaPreviewType.image,
                  source: source,
                  heroTag: 'media-$source',
                );
              }).toList()
            : [
                MediaPreviewItem(
                  id: widget.payload.url ?? 'media',
                  messageId: 'media',
                  type: (widget.payload.url?.toLowerCase().endsWith('.mp4') ?? false)
                      ? MediaPreviewType.video
                      : MediaPreviewType.image,
                  source: widget.payload.url ?? '',
                  heroTag: 'media-${widget.payload.url}',
                ),
              ];
        return DesktopMediaViewerWindow(
          items: items,
          initialIndex: widget.payload.initialIndex,
          isSubWindow: true,
          onClose: _handleClose,
        );

      case SubWindowType.chat:
        if (widget.controller != null) {
          return DesktopSubWindowChatView(
            payload: widget.payload,
            controller: widget.controller!,
            onClose: _handleClose,
          );
        }
        return Scaffold(
          body: Center(
            child: Text('独立聊天窗口：${widget.payload.title}'),
          ),
        );

      case SubWindowType.diagnostics:
        return Scaffold(
          appBar: AppBar(
            title: const Text('GotoIM 子窗口诊断'),
            actions: [
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: _handleClose,
              ),
            ],
          ),
          body: Center(
            child: Text(
              '当前子窗口 ID: ${widget.controller?.windowId}\n目标: ${widget.payload.targetId}',
              textAlign: TextAlign.center,
            ),
          ),
        );
    }
  }
}
