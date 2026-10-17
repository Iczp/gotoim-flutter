import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_navigation.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/session/application/session_list_controller.dart';
import '../media/media_preview.dart';
import '../native_window/native_window_payload.dart';
import '../platform/platform_facade.dart';

/// 独立窗口类型定义
enum WindowType {
  chat,
  miniApp,
  fileServer,
  media,
  diagnostics,
  settings,
  browser,
}

/// 窗口记录，用于管理和防止重复创建相同会话/应用的窗口
class WindowRecord {
  const WindowRecord({
    required this.targetId,
    required this.type,
    required this.title,
    required this.openedAt,
    this.windowId,
    this.nativeWindowId,
    this.extra,
  });

  /// 业务唯一标识（如 "chat:12345" 或 "miniapp:app-1"）
  final String targetId;

  /// 窗口类型
  final WindowType type;

  /// 窗口标题
  final String title;

  /// 打开时间
  final DateTime openedAt;

  /// 原生窗口数字 ID（兼容旧结构）
  final int? windowId;

  /// 原生窗口字符串 ID（如 desktop_multi_window UUID）
  final String? nativeWindowId;

  /// 附加参数
  final Map<String, dynamic>? extra;

  WindowRecord copyWith({
    String? targetId,
    WindowType? type,
    String? title,
    DateTime? openedAt,
    int? windowId,
    String? nativeWindowId,
    Map<String, dynamic>? extra,
  }) {
    return WindowRecord(
      targetId: targetId ?? this.targetId,
      type: type ?? this.type,
      title: title ?? this.title,
      openedAt: openedAt ?? this.openedAt,
      windowId: windowId ?? this.windowId,
      nativeWindowId: nativeWindowId ?? this.nativeWindowId,
      extra: extra ?? this.extra,
    );
  }
}

/// 统一跨平台独立窗口服务抽象 (WindowService Facade)
///
/// 核心契约：
/// 1. 桌面端（Windows / macOS / Linux）：创建或激活独立系统顶层窗口（HWND），维护 targetId -> WindowController；
/// 2. 移动端 / Web 端：自动降级为当前 App 内部页面导航（保持一致的调用语法）；
/// 3. 幂等激活：同一 Session 或应用已打开时，激活已有窗口，不重复创建。
abstract class WindowService {
  /// 打开或激活独立聊天窗口
  Future<void> openChat({
    required String sessionUnitId,
    int? ownerId,
    String? title,
  });

  /// 打开或激活独立微应用 / 工作台 H5 窗口
  Future<void> openMiniApp({
    required String appId,
    required String initialUrl,
    String? title,
  });

  /// 打开或激活独立网页浏览器窗口 (打开链接)
  Future<void> openWebBrowser({
    required String url,
    String? title,
    String? fallbackContent,
  });

  /// 打开或激活独立多媒体/文档预览窗口 (查看图片/视频)
  Future<void> openMediaViewer({
    required String mediaUrl,
    String? title,
    List<MediaPreviewItem>? items,
    int initialIndex = 0,
  });

  /// 打开或激活独立设置窗口
  Future<void> openSettings();

  /// 打开或激活局域网快传独立控制台
  Future<void> openLocalFileServer();

  /// 打开或激活独立开发诊断中心窗口
  Future<void> openDiagnostics();

  /// 激活或置顶已有窗口
  Future<void> bringToFront(String targetId);

  /// 关闭指定业务窗口
  Future<void> closeWindow(String targetId);

  /// 检查指定业务窗口是否已在独立视窗中打开
  bool isWindowOpen(String targetId);

  /// 获取当前所有已登记的独立窗口列表
  List<WindowRecord> get openWindows;

  /// 独立窗口列表变更流
  Stream<List<WindowRecord>> get openWindowsStream;
}

/// 统一窗口服务默认实现
class DefaultWindowService implements WindowService {
  DefaultWindowService({
    required this.platformFacade,
    this.accountInfoProvider,
  }) {
    _ensureIpcInitialized();
  }

  final PlatformFacade platformFacade;
  final Map<String, dynamic>? Function()? accountInfoProvider;

  final Map<String, WindowRecord> _registry = <String, WindowRecord>{};
  final Map<String, WindowController> _nativeControllers =
      <String, WindowController>{};
  final StreamController<List<WindowRecord>> _streamController =
      StreamController<List<WindowRecord>>.broadcast();

  bool _ipcInitialized = false;

  void _ensureIpcInitialized() {
    if (_ipcInitialized || !platformFacade.supportsMultipleWindows) return;
    _ipcInitialized = true;
    try {
      const mainIpcChannel = WindowMethodChannel(
        'gotoim/ipc_to_main',
        mode: ChannelMode.unidirectional,
      );
      mainIpcChannel.setMethodCallHandler((call) async {
        switch (call.method) {
          case 'sub_window_closed':
            final args = call.arguments as Map?;
            final targetId = args?['targetId'] as String?;
            if (targetId != null) {
              await closeWindow(targetId);
            }
            return true;
          default:
            return null;
        }
      });

      // 监听全局子窗口销毁/关闭事件
      onWindowsChanged.listen((_) async {
        try {
          final liveWindows = await WindowController.getAll();
          final liveWindowIds = liveWindows.map((w) => w.windowId).toSet();
          final deadKeys = <String>[];
          for (final entry in _nativeControllers.entries) {
            if (!liveWindowIds.contains(entry.value.windowId)) {
              deadKeys.add(entry.key);
            }
          }
          for (final key in deadKeys) {
            _nativeControllers.remove(key);
            _registry.remove(key);
          }
          if (deadKeys.isNotEmpty) {
            _notify();
          }
        } catch (_) {}
      });
    } catch (_) {}
  }

  @override
  List<WindowRecord> get openWindows => _registry.values.toList();

  @override
  Stream<List<WindowRecord>> get openWindowsStream => _streamController.stream;

  @override
  bool isWindowOpen(String targetId) {
    if (_registry.containsKey(targetId)) return true;
    if (targetId.toLowerCase() == 'tool:localfileserver' ||
        targetId.toLowerCase() == 'tool:fileserver') {
      return _registry.containsKey('tool:fileserver') ||
          _registry.containsKey('tool:localFileServer');
    }
    if (targetId.startsWith('chat:')) {
      final parts = targetId.split(':');
      final sessionUnitId = parts.last;
      return _registry.keys.any(
        (k) => k == targetId || k.endsWith(':$sessionUnitId'),
      );
    }
    return false;
  }

  @override
  Future<void> bringToFront(String targetId) async {
    final controller = _nativeControllers[targetId];
    if (controller != null) {
      try {
        await controller.show();
        await controller.invokeMethod('bringToFront');
        debugPrint(
          '[WindowService] Activated native HWND for $targetId (windowId=${controller.windowId})',
        );
        return;
      } catch (e) {
        debugPrint('[WindowService] Error bringing window to front: $e');
      }
    }
    final record = _registry[targetId];
    if (record != null) {
      debugPrint(
        '[WindowService] bringToFront: $targetId (title=${record.title})',
      );
    }
  }

  @override
  Future<void> closeWindow(String targetId) async {
    final controller = _nativeControllers.remove(targetId);
    if (controller != null) {
      try {
        await controller.hide();
      } catch (_) {}
    }
    bool removed = _registry.remove(targetId) != null;
    if (!removed && targetId.startsWith('chat:')) {
      final parts = targetId.split(':');
      final sessionUnitId = parts.last;
      final matchingKeys =
          _registry.keys.where((k) => k.endsWith(':$sessionUnitId')).toList();
      for (final k in matchingKeys) {
        _registry.remove(k);
        final c = _nativeControllers.remove(k);
        if (c != null) {
          try {
            c.hide();
          } catch (_) {}
        }
        removed = true;
      }
    }
    if (removed) {
      _notify();
      debugPrint('[WindowService] closeWindow: $targetId');
    }
  }

  /// 创建真正的原生顶层操作系统窗口 (HWND)
  Future<void> _openNativeSubWindow({
    required String targetId,
    required WindowType type,
    required String title,
    required NativeWindowPayload payload,
  }) async {
    _ensureIpcInitialized();
    try {
      final controller = await WindowController.create(
        WindowConfiguration(
          arguments: payload.toJsonString(),
          hiddenAtLaunch: false,
        ),
      );
      await controller.show();
      _nativeControllers[targetId] = controller;
      _registry[targetId] = WindowRecord(
        targetId: targetId,
        type: type,
        title: title,
        openedAt: DateTime.now(),
        nativeWindowId: controller.windowId,
        extra: payload.toJson(),
      );
      _notify();
      debugPrint(
        '[WindowService] Native multi-window created successfully: $targetId (windowId=${controller.windowId})',
      );
    } catch (e, stackTrace) {
      debugPrint(
        '[WindowService] Failed to create native sub-window for $targetId: $e\n$stackTrace',
      );
      _registry.remove(targetId);
      _nativeControllers.remove(targetId);
      _notify();
      rethrow;
    }
  }

  @override
  Future<void> openChat({
    required String sessionUnitId,
    int? ownerId,
    String? title,
  }) async {
    final effectiveOwnerId = ownerId ?? 0;
    final targetId = 'chat:$effectiveOwnerId:$sessionUnitId';
    if (isWindowOpen(targetId)) {
      await bringToFront(targetId);
      return;
    }

    if (platformFacade.supportsMultipleWindows) {
      try {
        final payload = NativeWindowPayload(
          type: SubWindowType.chat,
          title: title ?? '聊天',
          targetId: targetId,
          sessionUnitId: sessionUnitId,
          ownerId: effectiveOwnerId,
        );
        await _openNativeSubWindow(
          targetId: targetId,
          type: WindowType.chat,
          title: title ?? '聊天',
          payload: payload,
        );
        return;
      } catch (e) {
        debugPrint(
          '[WindowService] Fallback to in-app navigation due to native multi-window error: $e',
        );
      }
    }

    // 移动端、Web 或回退模式：使用统一应用内路由
    final context = rootNavigatorKey.currentContext;
    if (context != null && context.mounted) {
      _registerWindow(
        targetId: targetId,
        type: WindowType.chat,
        title: title ?? '聊天',
        extra: <String, dynamic>{
          'sessionUnitId': sessionUnitId,
          'ownerId': effectiveOwnerId,
        },
      );
      try {
        final effectiveTitle = Uri.encodeQueryComponent(title ?? '聊天');
        final path =
            '/chat/${Uri.encodeComponent(sessionUnitId)}'
            '?ownerId=$effectiveOwnerId'
            '&title=$effectiveTitle';
        await SafeChatNavigator.pushChat(context, path);
      } finally {
        await closeWindow(targetId);
      }
    }
  }

  @override
  Future<void> openMiniApp({
    required String appId,
    required String initialUrl,
    String? title,
  }) async {
    final targetId = 'miniApp:$appId';
    if (isWindowOpen(targetId)) {
      await bringToFront(targetId);
      return;
    }

    if (platformFacade.supportsMultipleWindows) {
      try {
        final payload = NativeWindowPayload(
          type: SubWindowType.browser,
          title: title ?? '应用',
          targetId: targetId,
          url: initialUrl,
        );
        await _openNativeSubWindow(
          targetId: targetId,
          type: WindowType.miniApp,
          title: title ?? '应用',
          payload: payload,
        );
        return;
      } catch (e) {
        debugPrint('[WindowService] Native multi-window error: $e');
      }
    }

    final context = rootNavigatorKey.currentContext;
    if (context != null && context.mounted) {
      _registerWindow(
        targetId: targetId,
        type: WindowType.miniApp,
        title: title ?? '应用',
        extra: <String, dynamic>{'appId': appId, 'url': initialUrl},
      );
      try {
        final effectiveTitle = Uri.encodeQueryComponent(title ?? '微应用');
        final effectiveUrl = Uri.encodeQueryComponent(initialUrl);
        await context.push('/webview?url=$effectiveUrl&title=$effectiveTitle');
      } finally {
        await closeWindow(targetId);
      }
    }
  }

  @override
  Future<void> openWebBrowser({
    required String url,
    String? title,
    String? fallbackContent,
  }) async {
    final targetId = 'browser:$url';
    if (isWindowOpen(targetId)) {
      await bringToFront(targetId);
      return;
    }

    if (platformFacade.supportsMultipleWindows) {
      try {
        final payload = NativeWindowPayload(
          type: SubWindowType.browser,
          title: title ?? '网页浏览',
          targetId: targetId,
          url: url,
          fallbackContent: fallbackContent,
        );
        await _openNativeSubWindow(
          targetId: targetId,
          type: WindowType.browser,
          title: title ?? '网页浏览',
          payload: payload,
        );
        return;
      } catch (e) {
        debugPrint('[WindowService] Native browser error: $e');
      }
    }

    final context = rootNavigatorKey.currentContext;
    if (context != null && context.mounted) {
      _registerWindow(
        targetId: targetId,
        type: WindowType.browser,
        title: title ?? '网页浏览',
        extra: <String, dynamic>{'url': url},
      );
      try {
        final effectiveTitle = Uri.encodeQueryComponent(title ?? '网页');
        final effectiveUrl = Uri.encodeQueryComponent(url);
        await context.push('/webview?url=$effectiveUrl&title=$effectiveTitle');
      } finally {
        await closeWindow(targetId);
      }
    }
  }

  @override
  Future<void> openMediaViewer({
    required String mediaUrl,
    String? title,
    List<MediaPreviewItem>? items,
    int initialIndex = 0,
  }) async {
    final targetId = 'media:$mediaUrl';
    if (isWindowOpen(targetId)) {
      await bringToFront(targetId);
      return;
    }

    final previewItems =
        items ??
        [
          MediaPreviewItem(
            id: mediaUrl,
            messageId: 'direct',
            type:
                mediaUrl.toLowerCase().endsWith('.mp4') ||
                        mediaUrl.toLowerCase().endsWith('.mov')
                    ? MediaPreviewType.video
                    : MediaPreviewType.image,
            source: mediaUrl,
            heroTag: 'media-$mediaUrl',
          ),
        ];

    if (platformFacade.supportsMultipleWindows) {
      try {
        final payload = NativeWindowPayload(
          type: SubWindowType.media,
          title: title ?? '媒体预览',
          targetId: targetId,
          url: mediaUrl,
          initialIndex: initialIndex,
          mediaItems:
              previewItems
                  .map(
                    (i) => {
                      'id': i.id,
                      'messageId': i.messageId,
                      'source': i.source,
                    },
                  )
                  .toList(),
        );
        await _openNativeSubWindow(
          targetId: targetId,
          type: WindowType.media,
          title: title ?? '媒体预览',
          payload: payload,
        );
        return;
      } catch (e) {
        debugPrint('[WindowService] Native media viewer error: $e');
      }
    }

    final context = rootNavigatorKey.currentContext;
    if (context != null && context.mounted) {
      _registerWindow(
        targetId: targetId,
        type: WindowType.media,
        title: title ?? '媒体预览',
        extra: <String, dynamic>{'url': mediaUrl},
      );
      try {
        await MediaPreview.open(
          context,
          items: previewItems,
          initialIndex: initialIndex,
        );
      } finally {
        await closeWindow(targetId);
      }
    }
  }

  @override
  Future<void> openSettings() async {
    const targetId = 'tool:settings';
    if (isWindowOpen(targetId)) {
      await bringToFront(targetId);
      return;
    }

    if (platformFacade.supportsMultipleWindows) {
      try {
        final payload = NativeWindowPayload(
          type: SubWindowType.settings,
          title: '设置',
          targetId: targetId,
          extra: accountInfoProvider?.call(),
        );
        await _openNativeSubWindow(
          targetId: targetId,
          type: WindowType.settings,
          title: '设置',
          payload: payload,
        );
        return;
      } catch (e) {
        debugPrint('[WindowService] Native settings window error: $e');
      }
    }

    final context = rootNavigatorKey.currentContext;
    if (context != null && context.mounted) {
      _registerWindow(
        targetId: targetId,
        type: WindowType.settings,
        title: '设置',
      );
      try {
        await context.push('/settings');
      } finally {
        await closeWindow(targetId);
      }
    }
  }

  @override
  Future<void> openDiagnostics() async {
    const targetId = 'tool:diagnostics';
    if (isWindowOpen(targetId)) {
      await bringToFront(targetId);
      return;
    }

    if (platformFacade.supportsMultipleWindows) {
      try {
        final payload = const NativeWindowPayload(
          type: SubWindowType.settings,
          title: '开发诊断中心',
          targetId: targetId,
        );
        await _openNativeSubWindow(
          targetId: targetId,
          type: WindowType.diagnostics,
          title: '开发诊断中心',
          payload: payload,
        );
        return;
      } catch (e) {
        debugPrint('[WindowService] Native diagnostics error: $e');
      }
    }

    final context = rootNavigatorKey.currentContext;
    if (context != null && context.mounted) {
      _registerWindow(
        targetId: targetId,
        type: WindowType.diagnostics,
        title: '开发诊断中心',
      );
      try {
        await context.push('/diagnostics');
      } finally {
        await closeWindow(targetId);
      }
    }
  }

  @override
  Future<void> openLocalFileServer() async {
    const targetId = 'tool:localFileServer';
    if (isWindowOpen(targetId)) {
      await bringToFront(targetId);
      return;
    }

    if (platformFacade.supportsMultipleWindows) {
      try {
        final payload = const NativeWindowPayload(
          type: SubWindowType.browser,
          title: '局域网快传',
          targetId: targetId,
          url: 'http://127.0.0.1:8080',
        );
        await _openNativeSubWindow(
          targetId: targetId,
          type: WindowType.fileServer,
          title: '局域网快传',
          payload: payload,
        );
        return;
      } catch (e) {
        debugPrint('[WindowService] Native file server error: $e');
      }
    }

    final context = rootNavigatorKey.currentContext;
    if (context != null && context.mounted) {
      _registerWindow(
        targetId: targetId,
        type: WindowType.fileServer,
        title: '局域网快传',
      );
      try {
        await context.push('/fileserver');
      } finally {
        await closeWindow(targetId);
      }
    }
  }

  void _registerWindow({
    required String targetId,
    required WindowType type,
    required String title,
    Map<String, dynamic>? extra,
  }) {
    _registry[targetId] = WindowRecord(
      targetId: targetId,
      type: type,
      title: title,
      openedAt: DateTime.now(),
      extra: extra,
    );
    _notify();
  }

  void _notify() {
    if (!_streamController.isClosed) {
      _streamController.add(openWindows);
    }
  }
}

/// 全局 WindowService Provider
final Provider<WindowService> windowServiceProvider = Provider<WindowService>((
  ref,
) {
  final platformFacade = ref.watch(platformFacadeProvider);
  return DefaultWindowService(
    platformFacade: platformFacade,
    accountInfoProvider: () {
      try {
        final sessionList = ref.read(sessionListControllerProvider);
        final currentOwner = sessionList.currentOwner;
        final auth = ref.read(authControllerProvider);
        return {
          'displayName': currentOwner?.name ?? auth.accountName ?? '登录用户',
          'accountId':
              auth.currentUser?.userName ??
              (currentOwner != null ? '${currentOwner.id}' : '未知账号'),
          'avatarUrl': currentOwner?.imageUrl,
        };
      } catch (_) {
        return null;
      }
    },
  );
});
