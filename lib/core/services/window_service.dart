import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Rect, ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_navigation.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/chat/application/chat_controller.dart';
import '../../features/chat/data/models/chat_message.dart';
import '../../features/session/application/session_list_controller.dart';
import '../../features/session/data/models/chat_owner.dart';
import '../../features/session/data/session_change_bus.dart';
import '../../features/settings/presentation/desktop_settings_window.dart';
import '../browser/desktop_browser_window.dart';
import '../media/media_preview.dart';
import '../native_window/native_window_payload.dart';
import '../platform/platform_facade.dart';
import '../platform/windows/windows_window_adapter.dart';
import '../theme/theme_mode_controller.dart';
import '../widgets/desktop_tray_message_box.dart';
import 'file/file_picker_service.dart';
import 'tray_grouped_unread_provider.dart';
import 'tray_message_models.dart';
import 'package:image_picker/image_picker.dart' show XFile;

/// 独立窗口类型定义
enum WindowType {
  chat,
  miniApp,
  fileServer,
  media,
  diagnostics,
  settings,
  browser,
  tray,
  profileCard,
  screenCapture,
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

  Future<void> openTrayFlyout();

  /// 预热托盘未读消息独立浮窗（后台常驻不显示）
  Future<void> prewarmTrayFlyout();

  /// 预热头像资料卡独立浮窗（后台常驻不显示）
  Future<void> prewarmProfileCard();

  /// 移动并无夺焦展示头像资料卡浮窗
  Future<void> showProfileCardAt({
    required Map<String, dynamic> subjectData,
    required Rect localRect,
  });

  /// 隐藏头像资料卡浮窗
  Future<void> hideProfileCard();

  /// 切换当前激活的聊天身份并聚焦主视窗
  Future<void> switchOwner(int ownerId);

  /// 激活或置顶已有窗口
  Future<void> bringToFront(String targetId);

  /// 关闭指定业务窗口
  Future<void> closeWindow(String targetId, {String? windowId});

  /// 检查指定业务窗口是否已在独立视窗中打开
  bool isWindowOpen(String targetId);

  /// 获取当前所有已登记的独立窗口列表
  List<WindowRecord> get openWindows;

  /// 独立窗口列表变更流
  Stream<List<WindowRecord>> get openWindowsStream;

  /// 向对应会话的独立聊天子窗口推送实时消息
  Future<void> notifyChatMessage({
    required int ownerId,
    required String sessionUnitId,
    required Map<String, dynamic> messageData,
  });

  /// 通知对应会话的独立聊天子窗口刷新消息
  Future<void> notifyChatRefresh({
    required int ownerId,
    required String sessionUnitId,
  });

  /// 预热常驻桌面截图标注工具窗口
  Future<void> prewarmScreenCapture();

  /// 唤醒独立截图标注窗口进行桌面截取，返回标注合成后的图像字节流
  Future<Uint8List?> captureScreenInteractive({bool hideMainWindow = true});
}

typedef MessageSenderCallback =
    Future<ChatMessage> Function({
      required int ownerId,
      required String sessionUnitId,
      required String text,
      String? clientMessageId,
    });

typedef ImageSenderCallback =
    Future<ChatMessage> Function({
      required int ownerId,
      required String sessionUnitId,
      required List<int> bytes,
      String? fileName,
      String? caption,
    });

typedef FilesSenderCallback =
    Future<List<ChatMessage>> Function({
      required int ownerId,
      required String sessionUnitId,
      required List<String> filePaths,
      String? caption,
    });

typedef HistoryLoaderCallback =
    Future<List<Map<String, dynamic>>> Function({
      required int ownerId,
      required String sessionUnitId,
      int limit,
      int? beforeScore,
    });

/// 统一窗口服务默认实现
class DefaultWindowService implements WindowService {
  DefaultWindowService({
    required this.platformFacade,
    this.accountInfoProvider,
    this.messageSender,
    this.imageSender,
    this.filesSender,
    this.historyLoader,
    this.messageAction,
    this.onLogout,
    this.onThemeChanged,
    this.themeModeProvider,
    this.traySnapshotProvider,
    this.trayCommand,
    this.switchOwnerHandler,
    this.isSubWindow = false,
  }) {
    _ensureIpcInitialized();
  }

  final PlatformFacade platformFacade;
  Future<void> Function(Map arguments)? trayCommand;
  final Future<void> Function(int ownerId)? switchOwnerHandler;
  final bool isSubWindow;
  final TrayGroupedUnreadState Function()? traySnapshotProvider;
  static const _mainChannel = WindowMethodChannel(
    'gotoim/ipc_to_main',
    mode: ChannelMode.unidirectional,
  );
  Future<void> _requestMain(Map<String, dynamic> arguments) async {
    await _mainChannel.invokeMethod('open_window', arguments);
  }

  final Map<String, dynamic>? Function()? accountInfoProvider;
  final MessageSenderCallback? messageSender;
  final ImageSenderCallback? imageSender;
  final FilesSenderCallback? filesSender;
  final HistoryLoaderCallback? historyLoader;
  final Future<Map<String, dynamic>> Function(
    String action,
    ChatMessage message,
  )?
  messageAction;
  final Future<void> Function()? onLogout;
  final void Function(String themeMode)? onThemeChanged;
  final String Function()? themeModeProvider;

  final Map<String, WindowRecord> _registry = <String, WindowRecord>{};
  final Map<String, WindowController> _nativeControllers =
      <String, WindowController>{};
  final Map<String, WindowController> _reusableControllers =
      <String, WindowController>{};
  static const int _maxReusableControllers = 10;
  final Map<String, Future<void>> _pendingCreations = <String, Future<void>>{};
  Completer<Uint8List?>? _screenCaptureCompleter;

  final StreamController<List<WindowRecord>> _streamController =
      StreamController<List<WindowRecord>>.broadcast();

  bool _ipcInitialized = false;

  void _ensureIpcInitialized() {
    if (isSubWindow ||
        _ipcInitialized ||
        !platformFacade.supportsMultipleWindows) {
      return;
    }
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
            final windowId = args?['windowId'] as String?;
            if (targetId != null) {
              await closeWindow(targetId, windowId: windowId);
            }
            return true;

          case 'chat_send_message':
            final args = call.arguments as Map?;
            if (args != null && messageSender != null) {
              final sessionUnitId = args['sessionUnitId']?.toString() ?? '';
              final ownerId = (args['ownerId'] as num?)?.toInt() ?? 0;
              final content = args['content']?.toString() ?? '';
              final clientMessageId = args['clientMessageId']?.toString();
              try {
                final sent = await messageSender!(
                  ownerId: ownerId,
                  sessionUnitId: sessionUnitId,
                  text: content,
                  clientMessageId: clientMessageId,
                );
                return {
                  'success': true,
                  'clientMessageId': sent.clientMessageId ?? sent.localId,
                  'serverId': sent.serverId,
                  'state': sent.state,
                };
              } catch (e) {
                return {'success': false, 'error': '$e'};
              }
            }
            return {'success': false, 'error': 'messageSender not registered'};

          case 'chat_send_image':
            final args = call.arguments as Map?;
            if (args != null && imageSender != null) {
              final sessionUnitId = args['sessionUnitId']?.toString() ?? '';
              final ownerId = (args['ownerId'] as num?)?.toInt() ?? 0;
              final bytes = (args['bytes'] as List?)?.cast<int>() ?? <int>[];
              final fileName = args['fileName'] as String?;
              final caption = args['caption'] as String?;
              try {
                final sent = await imageSender!(
                  ownerId: ownerId,
                  sessionUnitId: sessionUnitId,
                  bytes: bytes,
                  fileName: fileName,
                  caption: caption,
                );
                return {
                  'success': true,
                  'clientMessageId': sent.clientMessageId ?? sent.localId,
                  'serverId': sent.serverId,
                  'state': sent.state,
                };
              } catch (e) {
                return {'success': false, 'error': '$e'};
              }
            }
            return {'success': false, 'error': 'imageSender not registered'};

          case 'chat_send_files':
            final args = call.arguments as Map?;
            if (args != null && filesSender != null) {
              final sessionUnitId = args['sessionUnitId']?.toString() ?? '';
              final ownerId = (args['ownerId'] as num?)?.toInt() ?? 0;
              final filePaths =
                  (args['filePaths'] as List?)?.cast<String>() ?? <String>[];
              final caption = args['caption'] as String?;
              try {
                final sentList = await filesSender!(
                  ownerId: ownerId,
                  sessionUnitId: sessionUnitId,
                  filePaths: filePaths,
                  caption: caption,
                );
                return {'success': true, 'count': sentList.length};
              } catch (e) {
                return {'success': false, 'error': '$e'};
              }
            }
            return {'success': false, 'error': 'filesSender not registered'};

          case 'chat_message_action':
            final args = call.arguments as Map;
            if (messageAction == null) {
              throw StateError('Message action unavailable');
            }
            return await messageAction!(
              args['action'] as String,
              ChatMessage.fromWindowPayload(args['message'] as Map),
            );
          case 'chat_load_history':
            final args = call.arguments as Map?;
            if (args != null && historyLoader != null) {
              final sessionUnitId = args['sessionUnitId']?.toString() ?? '';
              final ownerId = (args['ownerId'] as num?)?.toInt() ?? 0;
              try {
                final list = await historyLoader!(
                  ownerId: ownerId,
                  sessionUnitId: sessionUnitId,
                  beforeScore: (args['beforeScore'] as num?)?.toInt(),
                  limit: 30,
                );
                return list;
              } catch (_) {
                throw StateError('历史消息加载失败');
              }
            }
            return <dynamic>[];

          case 'app_logout':
            if (onLogout != null) {
              await onLogout!();
            }
            await closeAllSubWindows(isLogout: true);
            return true;

          case 'theme_changed':
            final args = call.arguments as Map?;
            final mode = args?['themeMode'] as String?;
            if (mode != null) {
              if (onThemeChanged != null) {
                onThemeChanged!(mode);
              }
              await broadcastToAllSubWindows('theme_changed', {
                'themeMode': mode,
              });
            }
            return true;

          case 'screen_capture_result':
            final args = call.arguments as Map?;
            final bytesList = (args?['bytes'] as List?)?.cast<int>();
            final imageBytes =
                bytesList != null && bytesList.isNotEmpty
                    ? Uint8List.fromList(bytesList)
                    : null;
            if (_screenCaptureCompleter != null &&
                !_screenCaptureCompleter!.isCompleted) {
              _screenCaptureCompleter!.complete(imageBytes);
            }
            return true;

          case 'screen_capture_cancel':
            if (_screenCaptureCompleter != null &&
                !_screenCaptureCompleter!.isCompleted) {
              _screenCaptureCompleter!.complete(null);
            }
            return true;

          case 'tray_command':
            if (trayCommand == null) throw StateError('Tray unavailable');
            await trayCommand!(call.arguments as Map);
            return true;
          case 'tray_snapshot':
            return traySnapshotProvider?.call().toJson() ??
                TrayGroupedUnreadState.empty.toJson();
          case 'focus_main':
            await bringToFront('main');
            return true;
          case 'switch_owner':
            final args = call.arguments as Map?;
            final ownerId = (args?['ownerId'] as num?)?.toInt();
            if (ownerId != null) {
              await switchOwner(ownerId);
            }
            return true;
          case 'open_window':
            final args = call.arguments as Map?;
            final type = args?['type'] as String?;
            if (type == 'switch_owner') {
              final ownerId = (args?['ownerId'] as num?)?.toInt();
              if (ownerId != null) {
                await switchOwner(ownerId);
              }
            } else if (type == 'tray') {
              await openTrayFlyout();
            } else if (type == 'browser') {
              await openWebBrowser(
                url: args!['url'] as String,
                title: args['title'] as String?,
              );
            } else if (type == 'media') {
              await openMediaViewer(
                mediaUrl: args!['url'] as String,
                initialIndex: (args['initialIndex'] as num?)?.toInt() ?? 0,
                items:
                    (args['items'] as List?)
                        ?.map(
                          (m) => MediaPreviewItem(
                            id: (m['id'] ?? m['source']) as String,
                            messageId: (m['messageId'] ?? 'preview') as String,
                            localPath: m['localPath'] as String?,
                            userId: m['userId'] as String?,
                            chatTarget: m['chatTarget'] as String?,
                            createdAt: DateTime.tryParse(
                              m['createdAt']?.toString() ?? '',
                            ),
                            fileName: m['fileName'] as String?,
                            thumbnail: m['thumbnail'] as String?,
                            source: m['source'] as String,
                            type:
                                m['type'] == 'video'
                                    ? MediaPreviewType.video
                                    : MediaPreviewType.image,
                            heroTag: m['source'] as String,
                          ),
                        )
                        .toList(),
              );
            } else if (type == 'chat') {
              await openChat(
                sessionUnitId: args!['sessionUnitId'] as String,
                ownerId: (args['ownerId'] as num?)?.toInt(),
                title: args['title'] as String?,
              );
            } else if (type == 'settings') {
              await openSettings();
            } else if (type == 'localFileServer') {
              await openLocalFileServer();
            } else if (type == 'diagnostics') {
              await openDiagnostics();
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
            _reusableControllers.remove(key);
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
    // Only support legacy 2-part chat key fallback (chat:sessionUnitId)
    final parts = targetId.split(':');
    if (parts.length == 2 && parts[0] == 'chat') {
      final sessionUnitId = parts[1];
      return _registry.keys.any(
        (k) => k == targetId || k.endsWith(':$sessionUnitId'),
      );
    }
    return false;
  }

  @override
  Future<void> switchOwner(int ownerId) async {
    if (isSubWindow) {
      return _requestMain({'type': 'switch_owner', 'ownerId': ownerId});
    }
    await switchOwnerHandler?.call(ownerId);
    await bringToFront('main');
  }

  @override
  Future<void> bringToFront(String targetId) async {
    if (targetId == 'main') {
      if (isSubWindow) {
        await _mainChannel.invokeMethod('focus_main');
        return;
      }
      await WindowsWindowAdapter.bringToFront();
      return;
    }
    var controller = _nativeControllers[targetId];
    if (controller == null && targetId.startsWith('chat:')) {
      final parts = targetId.split(':');
      if (parts.length == 2) {
        final sessionUnitId = parts[1];
        final matchKey = _nativeControllers.keys.firstWhere(
          (k) => k.endsWith(':$sessionUnitId'),
          orElse: () => '',
        );
        if (matchKey.isNotEmpty) {
          controller = _nativeControllers[matchKey];
        }
      }
    }
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
  Future<void> closeWindow(String targetId, {String? windowId}) async {
    if (targetId == 'tool:settings') {
      try {
        await _nativeControllers[targetId]?.invokeMethod('setModal', false);
        await WindowsWindowAdapter.setModal(false);
      } catch (_) {}
    }
    if (targetId == 'tool:screen_capture') {
      if (_screenCaptureCompleter != null &&
          !_screenCaptureCompleter!.isCompleted) {
        _screenCaptureCompleter!.complete(null);
      }
      _screenCaptureCompleter = null;
    }
    final currentController = _nativeControllers[targetId];
    if (windowId != null &&
        currentController != null &&
        currentController.windowId != windowId) {
      return;
    }
    final controller = _nativeControllers.remove(targetId);
    if (controller != null) {
      try {
        await controller.hide();
        _reusableControllers[targetId] = controller;
        if (_reusableControllers.length > _maxReusableControllers) {
          final oldestKey = _reusableControllers.keys.first;
          final evicted = _reusableControllers.remove(oldestKey);
          if (evicted != null) {
            try {
              await evicted.invokeMethod('disposeWindow');
            } catch (_) {}
          }
        }
      } catch (_) {}
    }
    bool removed = _registry.remove(targetId) != null;
    if (!removed && targetId.startsWith('chat:')) {
      final parts = targetId.split(':');
      if (parts.length == 2) {
        final sessionUnitId = parts[1];
        final matchingKeys =
            _registry.keys.where((k) => k.endsWith(':$sessionUnitId')).toList();
        for (final k in matchingKeys) {
          _registry.remove(k);
          final c = _nativeControllers.remove(k);
          if (c != null) {
            try {
              await c.hide();
              _reusableControllers[k] = c;
              if (_reusableControllers.length > _maxReusableControllers) {
                final oldestKey = _reusableControllers.keys.first;
                final evicted = _reusableControllers.remove(oldestKey);
                if (evicted != null) {
                  try {
                    await evicted.invokeMethod('disposeWindow');
                  } catch (_) {}
                }
              }
            } catch (_) {}
          }
          removed = true;
        }
      }
    }
    if (removed) {
      _notify();
      debugPrint('[WindowService] closeWindow: $targetId');
    }
  }

  Future<void> closeAllSubWindows({bool isLogout = false}) async {
    final targets = _registry.keys.toList();
    for (final target in targets) {
      await closeWindow(target);
    }
    if (isLogout) {
      for (final controller in _reusableControllers.values.toList()) {
        try {
          await controller.invokeMethod('account_logout');
          await controller.invokeMethod('disposeWindow');
        } catch (_) {}
      }
      _reusableControllers.clear();
      _nativeControllers.clear();
      _registry.clear();
      _notify();
    }
  }

  @override
  Future<void> notifyChatMessage({
    required int ownerId,
    required String sessionUnitId,
    required Map<String, dynamic> messageData,
  }) async {
    final targetId = 'chat:$ownerId:$sessionUnitId';
    final controller =
        _nativeControllers[targetId] ??
        _reusableControllers[targetId] ??
        _nativeControllers['chat:$sessionUnitId'] ??
        _reusableControllers['chat:$sessionUnitId'];
    if (controller != null) {
      try {
        await controller.invokeMethod('chat_receive_message', messageData);
        debugPrint('[WindowService] Pushed chat_receive_message to $targetId');
      } catch (e) {
        debugPrint('[WindowService] notifyChatMessage error: $e');
      }
    }
  }

  @override
  Future<void> notifyChatRefresh({
    required int ownerId,
    required String sessionUnitId,
  }) async {
    final targetId = 'chat:$ownerId:$sessionUnitId';
    final controller =
        _nativeControllers[targetId] ??
        _reusableControllers[targetId] ??
        _nativeControllers['chat:$sessionUnitId'] ??
        _reusableControllers['chat:$sessionUnitId'];
    if (controller != null) {
      try {
        await controller.invokeMethod('chat_refresh');
        debugPrint('[WindowService] Pushed chat_refresh to $targetId');
      } catch (e) {
        debugPrint('[WindowService] notifyChatRefresh error: $e');
      }
    }
  }

  Future<void> updateTraySnapshot(TrayGroupedUnreadState snapshot) async {
    for (final controller in [
      ..._nativeControllers.values,
      ..._reusableControllers.values,
    ]) {
      try {
        await controller.invokeMethod('tray_update', snapshot.toJson());
      } catch (_) {}
    }
  }

  Future<void> broadcastToAllSubWindows(
    String method, [
    dynamic arguments,
  ]) async {
    for (final controller in _nativeControllers.values) {
      try {
        await controller.invokeMethod(method, arguments);
      } catch (_) {}
    }
    for (final controller in _reusableControllers.values.toList()) {
      try {
        await controller.invokeMethod(method, arguments);
      } catch (_) {}
    }
  }

  @override
  Future<void> prewarmTrayFlyout() async {
    if (isSubWindow || !platformFacade.supportsMultipleWindows) return;
    const targetId = 'tool:tray';
    if (isWindowOpen(targetId) || _pendingCreations.containsKey(targetId)) return;
    final snapshot =
        traySnapshotProvider?.call() ?? TrayGroupedUnreadState.empty;
    try {
      await _openNativeSubWindow(
        targetId: targetId,
        type: WindowType.tray,
        title: '未读消息',
        payload: NativeWindowPayload(
          type: SubWindowType.tray,
          title: '未读消息',
          targetId: targetId,
          extra: {'traySnapshot': snapshot.toJson()},
        ),
        showImmediately: false,
      );
    } catch (_) {}
  }

  @override
  Future<void> prewarmProfileCard() async {
    if (isSubWindow || !platformFacade.supportsMultipleWindows) return;
    const targetId = 'tool:profile_card';
    if (isWindowOpen(targetId) || _pendingCreations.containsKey(targetId)) return;
    try {
      await _openNativeSubWindow(
        targetId: targetId,
        type: WindowType.profileCard,
        title: '资料卡',
        payload: const NativeWindowPayload(
          type: SubWindowType.profileCard,
          title: '资料卡',
          targetId: targetId,
        ),
        showImmediately: false,
      );
    } catch (_) {}
  }

  @override
  Future<void> showProfileCardAt({
    required Map<String, dynamic> subjectData,
    required Rect localRect,
  }) async {
    if (isSubWindow || !platformFacade.supportsMultipleWindows) return;
    const targetId = 'tool:profile_card';
    final pending = _pendingCreations[targetId];
    if (pending != null) {
      await pending;
    } else if (!isWindowOpen(targetId)) {
      await prewarmProfileCard();
    }
    final controller = _nativeControllers[targetId];
    if (controller == null) return;

    final windowRect = await WindowsWindowAdapter.getWindowRect();
    final int dpi = windowRect?['dpi'] ?? 96;
    final double scale = dpi / 96.0;
    final int clientLeft =
        windowRect?['clientLeft'] ?? (windowRect?['left'] ?? 0);
    final int clientTop =
        windowRect?['clientTop'] ?? (windowRect?['top'] ?? 0);
    final int clientWidth = windowRect?['clientWidth'] ??
        ((windowRect?['right'] ?? (clientLeft + 1280)) - clientLeft);
    final int clientHeight = windowRect?['clientHeight'] ??
        ((windowRect?['bottom'] ?? (clientTop + 800)) - clientTop);
    final int winRight = clientLeft + clientWidth;
    final int winBottom = clientTop + clientHeight;

    final int cardPhysicalWidth = (380 * scale).round();
    final int cardPhysicalHeight = (420 * scale).round();

    final int avatarPhysicalRight =
        clientLeft + (localRect.right * scale).round();
    final int avatarPhysicalLeft =
        clientLeft + (localRect.left * scale).round();
    final int avatarPhysicalTop =
        clientTop + (localRect.top * scale).round();

    // Default: flyout appears to the right of the avatar with 8px margin
    int targetX = avatarPhysicalRight + (8 * scale).round();
    // If it exceeds the right edge, pop to the left of the avatar
    if (targetX + cardPhysicalWidth > winRight) {
      targetX = avatarPhysicalLeft - cardPhysicalWidth - (8 * scale).round();
    }
    int targetY = avatarPhysicalTop - (8 * scale).round();
    if (targetY < clientTop) targetY = clientTop + (4 * scale).round();
    if (targetY + cardPhysicalHeight > winBottom) {
      targetY = winBottom - cardPhysicalHeight - (4 * scale).round();
    }

    await controller.invokeMethod('update_profile', subjectData);
    await controller.invokeMethod('position_flyout', {
      'x': targetX,
      'y': targetY,
      'width': cardPhysicalWidth,
      'height': cardPhysicalHeight,
      'noActivate': true,
    });
  }

  @override
  Future<void> hideProfileCard() async {
    const targetId = 'tool:profile_card';
    final controller = _nativeControllers[targetId];
    if (controller != null) {
      try {
        await controller.invokeMethod('hide_profile');
      } catch (_) {}
    }
  }

  @override
  Future<void> prewarmScreenCapture() async {
    if (isSubWindow || !platformFacade.supportsMultipleWindows) return;
    const targetId = 'tool:screen_capture';
    if (isWindowOpen(targetId) || _pendingCreations.containsKey(targetId)) return;
    try {
      await _openNativeSubWindow(
        targetId: targetId,
        type: WindowType.screenCapture,
        title: 'GotoIM 截图',
        payload: const NativeWindowPayload(
          type: SubWindowType.screenCapture,
          title: 'GotoIM 截图',
          targetId: targetId,
        ),
        showImmediately: false,
      );
    } catch (_) {}
  }

  @override
  Future<Uint8List?> captureScreenInteractive({bool hideMainWindow = true}) async {
    _ensureIpcInitialized();
    if (isSubWindow) {
      debugPrint('[WindowService] 子窗口不支持直接发起全局截屏');
      return null;
    }
    const targetId = 'tool:screen_capture';

    // 1. 若配置了截屏时隐藏主窗口，先最小化并微量延迟等待 Windows 桌面重绘
    if (hideMainWindow && !kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      await WindowsWindowAdapter.minimize();
      await Future<void>.delayed(const Duration(milliseconds: 220));
    }

    // 2. 底层 Win32 瞬间捕获全屏幕虚拟桌面位图
    final capResult = await WindowsWindowAdapter.captureScreen();
    if (capResult == null) {
      if (hideMainWindow && !kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        await WindowsWindowAdapter.bringToFront();
      }
      return null;
    }

    final rawPath = capResult['path'] as String? ?? '';
    final vx = (capResult['x'] as num?)?.toInt() ?? 0;
    final vy = (capResult['y'] as num?)?.toInt() ?? 0;
    final vw = (capResult['width'] as num?)?.toInt() ?? 1920;
    final vh = (capResult['height'] as num?)?.toInt() ?? 1080;
    final dpi = (capResult['dpi'] as num?)?.toInt() ?? 96;

    // 3. 复用或预热常驻截图标注子窗口
    final pending = _pendingCreations[targetId];
    if (pending != null) {
      await pending;
    } else if (!isWindowOpen(targetId)) {
      await prewarmScreenCapture();
    }
    final controller = _nativeControllers[targetId];
    if (controller == null) {
      if (hideMainWindow && !kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        await WindowsWindowAdapter.bringToFront();
      }
      return null;
    }

    _screenCaptureCompleter = Completer<Uint8List?>();

    // 4. 将截取的底图与虚拟屏幕尺寸传递至常驻子窗口，并瞬间唤醒置顶全屏
    try {
      await controller.invokeMethod('show_screen_capture', {
        'imagePath': rawPath,
        'x': vx,
        'y': vy,
        'width': vw,
        'height': vh,
        'dpi': dpi,
      });
    } catch (e) {
      debugPrint('[WindowService] 唤醒截图窗口异常: $e');
      if (hideMainWindow && !kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        await WindowsWindowAdapter.bringToFront();
      }
      return null;
    }

    final resultBytes = await _screenCaptureCompleter!.future;
    _screenCaptureCompleter = null;

    if (hideMainWindow && !kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      await WindowsWindowAdapter.bringToFront();
    }
    return resultBytes;
  }

  @override
  Future<void> openTrayFlyout() async {
    if (isSubWindow) return _requestMain({'type': 'tray'});
    const targetId = 'tool:tray';
    final snapshot =
        traySnapshotProvider?.call() ?? TrayGroupedUnreadState.empty;
    if (isWindowOpen(targetId)) {
      await _nativeControllers[targetId]?.invokeMethod(
        'tray_update',
        snapshot.toJson(),
      );
      await _nativeControllers[targetId]?.invokeMethod('tray_flyout');
      await bringToFront(targetId);
      return;
    }
    if (platformFacade.supportsMultipleWindows) {
      try {
        await _openNativeSubWindow(
          targetId: targetId,
          type: WindowType.tray,
          title: '未读消息',
          payload: NativeWindowPayload(
            type: SubWindowType.tray,
            title: '未读消息',
            targetId: targetId,
            extra: {'traySnapshot': snapshot.toJson()},
          ),
        );
        return;
      } catch (e) {
        debugPrint('[WindowService] openTrayFlyout native error: $e');
      }
    }
    final context = rootNavigatorKey.currentContext;
    if (context != null && context.mounted) {
      DesktopTrayMessageBox.show(context);
    }
  }

  /// 创建真正的原生顶层操作系统窗口 (HWND)
  Future<void> _openNativeSubWindow({
    required String targetId,
    required WindowType type,
    required String title,
    required NativeWindowPayload payload,
    bool showImmediately = true,
  }) async {
    final pending = _pendingCreations[targetId];
    if (pending != null) {
      await pending;
      return;
    }

    final completer = Completer<void>();
    _pendingCreations[targetId] = completer.future.catchError((_) {});

    _ensureIpcInitialized();
    try {
      final currentTheme = themeModeProvider?.call() ?? 'system';
      final updatedExtra = <String, dynamic>{
        ...?payload.extra,
        'themeMode': currentTheme,
      };
      final effectivePayload = payload.copyWith(extra: updatedExtra);

      final cachedController = _reusableControllers.remove(targetId);
      if (cachedController != null) {
        try {
          await cachedController.invokeMethod(
            'update_payload',
            effectivePayload.toJson(),
          );
          await cachedController.invokeMethod('chat_refresh');
        } catch (_) {}
        if (showImmediately) {
          if (type == WindowType.settings) {
            try {
              await cachedController.invokeMethod('setModal', true);
            } catch (_) {}
          } else if (type != WindowType.profileCard &&
              type != WindowType.tray &&
              type != WindowType.screenCapture) {
            try {
              await cachedController.invokeMethod('center');
            } catch (_) {}
          }
          await cachedController.show();
          await cachedController.invokeMethod('bringToFront');
        } else {
          await cachedController.hide();
        }
        _nativeControllers[targetId] = cachedController;
        _registry[targetId] = WindowRecord(
          targetId: targetId,
          type: type,
          title: title,
          openedAt: DateTime.now(),
          nativeWindowId: cachedController.windowId,
          extra: effectivePayload.toJson(),
        );
        _notify();
        completer.complete();
        return;
      }

      final controller = await WindowController.create(
        WindowConfiguration(
          arguments: effectivePayload.toJsonString(),
          hiddenAtLaunch: true,
        ),
      );
      if (showImmediately) {
        if (type == WindowType.settings) {
          try {
            await controller.invokeMethod('setModal', true);
          } catch (_) {}
        }
        await controller.show();
      } else {
        await controller.hide();
      }
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
      completer.complete();
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
      completer.completeError(e, stackTrace);
      rethrow;
    } finally {
      _pendingCreations.remove(targetId);
    }
  }

  @override
  Future<void> openChat({
    required String sessionUnitId,
    int? ownerId,
    String? title,
  }) async {
    if (isSubWindow) {
      return _requestMain({
        'type': 'chat',
        'sessionUnitId': sessionUnitId,
        'ownerId': ownerId,
        'title': title,
      });
    }
    final effectiveOwnerId = ownerId ?? 0;
    final targetId = 'chat:$effectiveOwnerId:$sessionUnitId';
    if (isWindowOpen(targetId) || _pendingCreations.containsKey(targetId)) {
      final pending = _pendingCreations[targetId];
      if (pending != null) await pending;
      await bringToFront(targetId);
      await notifyChatRefresh(
        ownerId: effectiveOwnerId,
        sessionUnitId: sessionUnitId,
      );
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
    if (isSubWindow) {
      return _requestMain({
        'type': 'browser',
        'url': initialUrl,
        'title': title,
      });
    }
    final targetId = 'miniApp:$appId';
    if (isWindowOpen(targetId) || _pendingCreations.containsKey(targetId)) {
      final pending = _pendingCreations[targetId];
      if (pending != null) await pending;
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
    if (isSubWindow) {
      return _requestMain({'type': 'browser', 'url': url, 'title': title});
    }
    const targetId = 'tool:browser';
    final payload = NativeWindowPayload(
      type: SubWindowType.browser,
      title: title ?? '网页浏览',
      targetId: targetId,
      url: url,
      fallbackContent: fallbackContent,
    );

    if (isWindowOpen(targetId)) {
      final controller = _nativeControllers[targetId];
      if (controller != null) {
        final currentTheme = themeModeProvider?.call() ?? 'system';
        final effectivePayload = payload.copyWith(
          extra: {'themeMode': currentTheme},
        );
        try {
          await controller.invokeMethod('browser_add_tab', {
            'url': url,
            'title': title,
          });
        } catch (_) {
          await controller.invokeMethod(
            'update_payload',
            effectivePayload.toJson(),
          );
        }
        await bringToFront(targetId);
        return;
      }
    }

    if (platformFacade.supportsMultipleWindows) {
      try {
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
      if (platformFacade.isDesktop) {
        await DesktopBrowserWindow.open(
          context,
          url: url,
          title: title,
          fallbackContent: fallbackContent,
        );
        return;
      }
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
    if (isSubWindow) {
      return _requestMain({
        'type': 'media',
        'url': mediaUrl,
        'initialIndex': initialIndex,
        'items':
            items
                ?.map(
                  (i) => {
                    'id': i.id,
                    'messageId': i.messageId,
                    'source': i.source,
                    'type': i.type.name,
                    'localPath': i.localPath,
                    'userId': i.userId,
                    'chatTarget': i.chatTarget,
                    'createdAt': i.createdAt?.toIso8601String(),
                    'fileName': i.fileName,
                    'thumbnail': i.thumbnail,
                  },
                )
                .toList(),
      });
    }

    const targetId = 'tool:media';
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
                  'type': i.type.name,
                  'source': i.source,
                  'localPath': i.localPath,
                  'userId': i.userId,
                  'chatTarget': i.chatTarget,
                  'createdAt': i.createdAt?.toIso8601String(),
                  'fileName': i.fileName,
                  'thumbnail': i.thumbnail,
                },
              )
              .toList(),
    );

    if (isWindowOpen(targetId)) {
      final controller = _nativeControllers[targetId];
      if (controller != null) {
        final currentTheme = themeModeProvider?.call() ?? 'system';
        final effectivePayload = payload.copyWith(
          extra: {'themeMode': currentTheme},
        );
        await controller.invokeMethod(
          'update_payload',
          effectivePayload.toJson(),
        );
        await bringToFront(targetId);
        return;
      }
    }

    if (platformFacade.supportsMultipleWindows) {
      try {
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
    if (isSubWindow) return _requestMain({'type': 'settings'});
    const targetId = 'tool:settings';
    if (isWindowOpen(targetId) || _pendingCreations.containsKey(targetId)) {
      final pending = _pendingCreations[targetId];
      if (pending != null) await pending;
      try {
        await _nativeControllers[targetId]?.invokeMethod('setModal', true);
      } catch (_) {}
      await bringToFront(targetId);
      return;
    }

    if (platformFacade.supportsMultipleWindows) {
      try {
        final currentTheme = themeModeProvider?.call() ?? 'system';
        final payload = NativeWindowPayload(
          type: SubWindowType.settings,
          title: '设置',
          targetId: targetId,
          extra: {'themeMode': currentTheme},
        );
        await _openNativeSubWindow(
          targetId: targetId,
          type: WindowType.settings,
          title: '设置',
          payload: payload,
        );
        return;
      } catch (e) {
        debugPrint('[WindowService] Native settings error: $e');
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
        if (platformFacade.isDesktop) {
          await DesktopSettingsWindow.open(context);
        } else {
          await context.push('/settings');
        }
      } finally {
        await closeWindow(targetId);
      }
      return;
    }

    _registerWindow(targetId: targetId, type: WindowType.settings, title: '设置');
  }

  @override
  Future<void> openDiagnostics() async {
    if (isSubWindow) return _requestMain({'type': 'diagnostics'});
    const targetId = 'tool:diagnostics';
    if (isWindowOpen(targetId) || _pendingCreations.containsKey(targetId)) {
      final pending = _pendingCreations[targetId];
      if (pending != null) await pending;
      await bringToFront(targetId);
      return;
    }

    if (platformFacade.supportsMultipleWindows) {
      try {
        final currentTheme = themeModeProvider?.call() ?? 'system';
        final payload = NativeWindowPayload(
          type: SubWindowType.diagnostics,
          title: '开发诊断中心',
          targetId: targetId,
          extra: {'themeMode': currentTheme},
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
    if (isSubWindow) return _requestMain({'type': 'localFileServer'});
    const targetId = 'tool:localFileServer';
    if (isWindowOpen(targetId) || _pendingCreations.containsKey(targetId)) {
      final pending = _pendingCreations[targetId];
      if (pending != null) await pending;
      await bringToFront(targetId);
      return;
    }

    if (platformFacade.supportsMultipleWindows) {
      try {
        final currentTheme = themeModeProvider?.call() ?? 'system';
        final payload = NativeWindowPayload(
          type: SubWindowType.localFileServer,
          title: '局域网快传',
          targetId: targetId,
          extra: {'themeMode': currentTheme},
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
        await context.push('/local-file-server');
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
  final sessionChangeBus = ref.watch(sessionChangeBusProvider);

  late final DefaultWindowService service;
  ref.listen(trayGroupedUnreadProvider, (previous, next) {
    unawaited(service.updateTraySnapshot(next));
  });
  ref.listen(themeModeControllerProvider, (previous, next) {
    if (previous != next) {
      unawaited(
        service.broadcastToAllSubWindows('theme_changed', {
          'themeMode': next.name,
        }),
      );
    }
  });
  service = DefaultWindowService(
    platformFacade: platformFacade,
    traySnapshotProvider: () => ref.read(trayGroupedUnreadProvider),
    switchOwnerHandler: (ownerId) async {
      try {
        final controller = ref.read(sessionListControllerProvider);
        final target = controller.owners.firstWhere(
          (o) => o.id == ownerId,
          orElse:
              () => ChatOwner(
                id: ownerId,
                name: '',
                imageUrl: null,
                typeDescription: '',
              ),
        );
        await controller.selectOwner(target);
      } catch (_) {}
    },
    themeModeProvider: () {
      try {
        return ref.read(themeModeControllerProvider).name;
      } catch (_) {
        return 'system';
      }
    },
    messageSender: ({
      required int ownerId,
      required String sessionUnitId,
      required String text,
      String? clientMessageId,
    }) async {
      final repo = ref.read(messageRepositoryProvider);
      final sent = await repo.sendText(
        ownerId: ownerId,
        sessionUnitId: sessionUnitId,
        text: text,
        clientMessageId: clientMessageId,
      );
      // 同时推送给已打开的子窗口自身
      service.notifyChatMessage(
        ownerId: ownerId,
        sessionUnitId: sessionUnitId,
        messageData: sent.toWindowPayload(),
      );
      return sent;
    },
    imageSender: ({
      required int ownerId,
      required String sessionUnitId,
      required List<int> bytes,
      String? fileName,
      String? caption,
    }) async {
      final repo = ref.read(messageRepositoryProvider);
      final effectiveName =
          fileName ?? 'image_${DateTime.now().millisecondsSinceEpoch}.png';
      final selected = await SelectedFile.fromBytes(
        Uint8List.fromList(bytes),
        name: effectiveName,
        mimeType: 'image/png',
      );
      final local = await repo.createLocalImage(
        ownerId: ownerId,
        sessionUnitId: sessionUnitId,
        file: selected,
      );
      service.notifyChatMessage(
        ownerId: ownerId,
        sessionUnitId: sessionUnitId,
        messageData: local.toWindowPayload(),
      );
      final sent = await repo.sendLocalImage(local: local, file: selected);
      service.notifyChatMessage(
        ownerId: ownerId,
        sessionUnitId: sessionUnitId,
        messageData: sent.toWindowPayload(),
      );
      if (caption != null && caption.trim().isNotEmpty) {
        await repo.sendText(
          ownerId: ownerId,
          sessionUnitId: sessionUnitId,
          text: caption.trim(),
        );
      }
      return sent;
    },
    filesSender: ({
      required int ownerId,
      required String sessionUnitId,
      required List<String> filePaths,
      String? caption,
    }) async {
      final repo = ref.read(messageRepositoryProvider);
      final results = <ChatMessage>[];
      for (final p in filePaths) {
        final xfile = XFile(p);
        final selected = await SelectedFile.fromXFile(xfile);
        final local = await repo.createLocalFile(
          ownerId: ownerId,
          sessionUnitId: sessionUnitId,
          file: selected,
        );
        service.notifyChatMessage(
          ownerId: ownerId,
          sessionUnitId: sessionUnitId,
          messageData: local.toWindowPayload(),
        );
        final sent = await repo.sendLocalFile(local: local, file: selected);
        service.notifyChatMessage(
          ownerId: ownerId,
          sessionUnitId: sessionUnitId,
          messageData: sent.toWindowPayload(),
        );
        results.add(sent);
      }
      if (caption != null && caption.trim().isNotEmpty) {
        await repo.sendText(
          ownerId: ownerId,
          sessionUnitId: sessionUnitId,
          text: caption.trim(),
        );
      }
      return results;
    },
    historyLoader: ({
      required int ownerId,
      required String sessionUnitId,
      int limit = 30,
      int? beforeScore,
    }) async {
      final repo = ref.read(messageRepositoryProvider);
      var page =
          beforeScore == null
              ? await repo.loadInitialLocal(
                ownerId: ownerId,
                sessionUnitId: sessionUnitId,
                limit: limit,
              )
              : await repo.loadHistory(
                ownerId: ownerId,
                sessionUnitId: sessionUnitId,
                beforeScore: beforeScore,
                limit: limit,
              );
      if (beforeScore == null && page.items.isEmpty) {
        page = await repo.loadHistory(
          ownerId: ownerId,
          sessionUnitId: sessionUnitId,
          limit: limit,
        );
      }
      return page.items.reversed.map((m) => m.toWindowPayload()).toList();
    },
    messageAction: (action, message) async {
      if (action == 'voice') {
        await ref
            .read(audioPlaybackServiceProvider)
            .toggle(
              messageId: message.localId,
              localPath: message.localFilePath,
              url: message.mediaUrl,
            );
        return {'success': true};
      }
      final transfer = ref.read(attachmentTransferServiceProvider);
      final source = message.mediaUrl ?? '';
      final fileName =
          message.fileName.isEmpty ? 'attachment' : message.fileName;
      if (action == 'cancel') {
        await transfer.cancel(message.localId);
      } else if (action == 'saveAs') {
        await transfer.saveAs(
          id: message.localId,
          source: source,
          fileName: fileName,
          userId: message.ownerId.toString(),
          chatTarget: message.sessionUnitId,
          messageDate: message.createdAt,
        );
      } else if (action == 'open') {
        await transfer.open(
          id: message.localId,
          source: source,
          fileName: fileName,
          userId: message.ownerId.toString(),
          chatTarget: message.sessionUnitId,
          messageDate: message.createdAt,
        );
      } else {
        await transfer.download(
          id: message.localId,
          source: source,
          fileName: fileName,
          userId: message.ownerId.toString(),
          chatTarget: message.sessionUnitId,
          messageDate: message.createdAt,
        );
      }
      final state = transfer.stateFor(message.localId);
      if (state.error != null) throw StateError('附件处理失败: ${state.error}');
      return {
        'success': true,
        'localPath': state.localPath,
        'status': state.status.name,
      };
    },
    onLogout: () async {
      await ref.read(authControllerProvider.notifier).logout();
    },
    onThemeChanged: (mode) {
      final target = ThemeMode.values.firstWhere(
        (e) => e.name == mode,
        orElse: () => ThemeMode.system,
      );
      ref.read(themeModeControllerProvider.notifier).setThemeMode(target);
    },
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

  // 监听全局会话变更总线，当收到任何消息或会话更新时，自动通知对应的独立子窗口刷新
  final sub = sessionChangeBus.events.listen((event) {
    if (event.sessionUnitId.isNotEmpty) {
      service.notifyChatRefresh(
        ownerId: event.ownerId,
        sessionUnitId: event.sessionUnitId,
      );
    }
  });

  ref.onDispose(() {
    sub.cancel();
  });

  return service;
});
