import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_navigation.dart';
import '../platform/platform_facade.dart';

/// 独立窗口类型定义
enum WindowType { chat, miniApp, fileServer, media, diagnostics, settings }

/// 窗口记录，用于管理和防止重复创建相同会话/应用的窗口
class WindowRecord {
  const WindowRecord({
    required this.targetId,
    required this.type,
    required this.title,
    required this.openedAt,
    this.windowId,
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

  /// 原生窗口 ID（桌面端多窗口场景）
  final int? windowId;

  /// 附加参数
  final Map<String, dynamic>? extra;

  WindowRecord copyWith({
    String? targetId,
    WindowType? type,
    String? title,
    DateTime? openedAt,
    int? windowId,
    Map<String, dynamic>? extra,
  }) {
    return WindowRecord(
      targetId: targetId ?? this.targetId,
      type: type ?? this.type,
      title: title ?? this.title,
      openedAt: openedAt ?? this.openedAt,
      windowId: windowId ?? this.windowId,
      extra: extra ?? this.extra,
    );
  }
}

/// 统一跨平台独立窗口服务抽象 (WindowService Facade)
///
/// 核心契约：
/// 1. 桌面端（Windows / macOS / Linux）：创建或激活独立系统窗口，维护 targetId -> windowId；
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

  /// 打开或激活局域网快传独立控制台
  Future<void> openLocalFileServer();

  /// 打开或激活独立多媒体/文档预览窗口
  Future<void> openMediaViewer({required String mediaUrl, String? title});

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
  DefaultWindowService({required this.platformFacade});

  final PlatformFacade platformFacade;

  final Map<String, WindowRecord> _registry = <String, WindowRecord>{};
  final StreamController<List<WindowRecord>> _streamController =
      StreamController<List<WindowRecord>>.broadcast();

  @override
  List<WindowRecord> get openWindows => _registry.values.toList();

  @override
  Stream<List<WindowRecord>> get openWindowsStream => _streamController.stream;

  @override
  bool isWindowOpen(String targetId) => _registry.containsKey(targetId);

  @override
  Future<void> bringToFront(String targetId) async {
    final record = _registry[targetId];
    if (record == null) return;
    debugPrint(
      '[WindowService] bringToFront: $targetId (title=${record.title})',
    );
    // 在原生桌面端支持多窗口插件时，此处会调用原生通道激活窗口。
  }

  @override
  Future<void> closeWindow(String targetId) async {
    if (_registry.remove(targetId) != null) {
      _notify();
      debugPrint('[WindowService] closeWindow: $targetId');
    }
  }

  @override
  Future<void> openChat({
    required String sessionUnitId,
    int? ownerId,
    String? title,
  }) async {
    final targetId = 'chat:$sessionUnitId';
    if (isWindowOpen(targetId)) {
      await bringToFront(targetId);
      return;
    }

    _registerWindow(
      targetId: targetId,
      type: WindowType.chat,
      title: title ?? '聊天',
      extra: <String, dynamic>{
        'sessionUnitId': sessionUnitId,
        'ownerId': ownerId,
      },
    );

    // 移动端、Web 或未启用独立系统窗口时，使用统一应用内路由
    final context = rootNavigatorKey.currentContext;
    if (context != null && context.mounted) {
      final effectiveTitle = Uri.encodeQueryComponent(title ?? '聊天');
      final path =
          '/chat/${Uri.encodeComponent(sessionUnitId)}'
          '?ownerId=${ownerId ?? 0}'
          '&title=$effectiveTitle';
      await SafeChatNavigator.pushChat(context, path);
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

    _registerWindow(
      targetId: targetId,
      type: WindowType.miniApp,
      title: title ?? '应用',
      extra: <String, dynamic>{'appId': appId, 'url': initialUrl},
    );

    final context = rootNavigatorKey.currentContext;
    if (context != null && context.mounted) {
      final effectiveTitle = Uri.encodeQueryComponent(title ?? '微应用');
      final effectiveUrl = Uri.encodeQueryComponent(initialUrl);
      context.push('/webview?url=$effectiveUrl&title=$effectiveTitle');
    }
  }

  @override
  Future<void> openLocalFileServer() async {
    const targetId = 'tool:localFileServer';
    if (isWindowOpen(targetId)) {
      await bringToFront(targetId);
      return;
    }

    _registerWindow(
      targetId: targetId,
      type: WindowType.fileServer,
      title: '局域网快传',
    );

    final context = rootNavigatorKey.currentContext;
    if (context != null && context.mounted) {
      context.push('/local-file-server');
    }
  }

  @override
  Future<void> openMediaViewer({
    required String mediaUrl,
    String? title,
  }) async {
    final targetId = 'media:$mediaUrl';
    if (isWindowOpen(targetId)) {
      await bringToFront(targetId);
      return;
    }

    _registerWindow(
      targetId: targetId,
      type: WindowType.media,
      title: title ?? '媒体预览',
      extra: <String, dynamic>{'url': mediaUrl},
    );

    // 默认通过大图/视频全屏页展示
    final context = rootNavigatorKey.currentContext;
    if (context != null && context.mounted) {
      context.push('/webview?url=${Uri.encodeQueryComponent(mediaUrl)}');
    }
  }

  @override
  Future<void> openDiagnostics() async {
    const targetId = 'tool:diagnostics';
    if (isWindowOpen(targetId)) {
      await bringToFront(targetId);
      return;
    }

    _registerWindow(
      targetId: targetId,
      type: WindowType.diagnostics,
      title: '开发诊断中心',
    );

    final context = rootNavigatorKey.currentContext;
    if (context != null && context.mounted) {
      context.push('/diagnostics');
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
  return DefaultWindowService(platformFacade: platformFacade);
});
