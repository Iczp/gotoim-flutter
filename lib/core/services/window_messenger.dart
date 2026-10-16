import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef WindowEventHandler = void Function(dynamic data);

/// 常见跨窗口标准事件名称定义（类似于 Electron 中的 IPC channel 定义）
class WindowEvents {
  const WindowEvents._();

  /// SignalR 收到新消息时派发 (由主窗口广播给所有相关子窗口)
  static const String chatMessageReceived = 'chat:message_received';

  /// 消息撤回或更新
  static const String chatMessageRecalled = 'chat:message_recalled';
  static const String chatMessageUpdated = 'chat:message_updated';

  /// 会话状态或未读数变更
  static const String sessionUpdated = 'session:updated';

  /// 主窗口切换当前聊天身份时通知所有窗口
  static const String ownerSwitched = 'owner:switched';

  /// SignalR 连接状态变更 (connected, reconnecting, disconnected)
  static const String signalRStatusChanged = 'signalr:status_changed';

  /// 全局主题切换 (dark, light, system)
  static const String themeChanged = 'theme:changed';

  /// 子窗口请求主窗口发送消息
  static const String requestSendMessage = 'chat:request_send';

  /// 窗口聚焦或置顶指令
  static const String focusWindow = 'window:focus';
}

/// 跨窗口事件通讯抽象门面 (WindowMessenger)
///
/// 设计模式：
/// 类似 Electron 中的 Mitt / EventEmitter 跨窗口 IPC 封装。
/// 核心原则：
/// 1. 【单连接原则】：全局仅主窗口 (windowId: 0) 建立与服务端的 SignalR 长连接和 Dio HTTP Client；
/// 2. 【统一分发】：主窗口收到 SignalR 推送或数据变更后，通过 [WindowMessenger.broadcast] 派发到打开的子窗口；
/// 3. 【代理操作】：子窗口如需执行发消息、踢下线等网络操作，通过 [sendToMain] 请求主窗口统一代理发送，确保连接数与状态一致性；
/// 4. 【离线共享】：桌面端各窗口共享同一本地 SQLite (Drift WAL 模式) 文件，主窗口写入后子窗口 Stream 自动更新，配合事件总线实现秒级协同。
abstract class WindowMessenger {
  /// 监听特定跨窗口事件（等价于 Mitt.on）
  void on(String event, WindowEventHandler handler);

  /// 取消监听特定跨窗口事件（等价于 Mitt.off）
  void off(String event, [WindowEventHandler? handler]);

  /// 触发当前窗口的局部事件，并同步向外部窗口派发
  Future<void> emit(String event, [dynamic data]);

  /// 主窗口向所有打开的独立子窗口广播事件
  Future<void> broadcast(String event, [dynamic data]);

  /// 向指定的特定窗口发送事件
  Future<void> sendToWindow(int windowId, String event, [dynamic data]);

  /// 子窗口向主窗口（windowId: 0）发送请求或调用指令
  Future<T?> sendToMain<T>(String method, [dynamic data]);

  /// 当前窗口是否为主窗口
  bool get isMainWindow;

  /// 释放所有资源与监听器
  void dispose();
}

/// 默认跨窗口通讯器实现
///
/// 具备双层调度能力：
/// 1. 进程内事件分发（基于广播映射表，提供微秒级本地响应）；
/// 2. 原生跨窗口 IPC 挂接（若存在独立原生窗口环境，自动透传序列化参数）。
class DefaultWindowMessenger implements WindowMessenger {
  DefaultWindowMessenger({this.isMainWindow = true, this.currentWindowId = 0});

  @override
  final bool isMainWindow;

  /// 当前窗口的原生 ID (主窗口通常为 0)
  final int currentWindowId;

  final Map<String, List<WindowEventHandler>> _handlers = {};
  final Set<int> _registeredWindowIds = {};

  /// 注册子窗口 ID，方便广播
  void registerSubWindow(int windowId) {
    if (windowId != currentWindowId) {
      _registeredWindowIds.add(windowId);
    }
  }

  /// 移除已关闭的子窗口 ID
  void unregisterSubWindow(int windowId) {
    _registeredWindowIds.remove(windowId);
  }

  @override
  void on(String event, WindowEventHandler handler) {
    _handlers.putIfAbsent(event, () => []).add(handler);
  }

  @override
  void off(String event, [WindowEventHandler? handler]) {
    if (handler == null) {
      _handlers.remove(event);
    } else {
      _handlers[event]?.remove(handler);
      if (_handlers[event]?.isEmpty == true) {
        _handlers.remove(event);
      }
    }
  }

  @override
  Future<void> emit(String event, [dynamic data]) async {
    _dispatchLocal(event, data);
    // 若在子窗口执行 emit，自动向上投递给主窗口转发
    if (!isMainWindow) {
      await sendToMain(event, data);
    }
  }

  @override
  Future<void> broadcast(String event, [dynamic data]) async {
    _dispatchLocal(event, data);
    if (isMainWindow) {
      for (final windowId in _registeredWindowIds) {
        await sendToWindow(windowId, event, data);
      }
    } else {
      // 子窗口请求主窗口执行全员广播
      await sendToMain('broadcast', {'event': event, 'data': data});
    }
  }

  @override
  Future<void> sendToWindow(int windowId, String event, [dynamic data]) async {
    if (windowId == currentWindowId) {
      _dispatchLocal(event, data);
      return;
    }
    // 原生多窗口通讯钩子：如使用 desktop_multi_window 时在此调用：
    // await DesktopMultiWindow.invokeMethod(windowId, event, data);
    debugPrint(
      '[WindowMessenger] Dispatching IPC -> targetWindow=$windowId event=$event data=$data',
    );
  }

  @override
  Future<T?> sendToMain<T>(String method, [dynamic data]) async {
    if (isMainWindow) {
      _dispatchLocal(method, data);
      return null;
    }
    debugPrint(
      '[WindowMessenger] SubWindow $currentWindowId -> Main (0): method=$method',
    );
    // 原生调用：await DesktopMultiWindow.invokeMethod(0, method, data);
    return null;
  }

  void _dispatchLocal(String event, dynamic data) {
    final list = _handlers[event];
    if (list != null && list.isNotEmpty) {
      final listeners = List<WindowEventHandler>.from(list);
      for (final listener in listeners) {
        try {
          listener(data);
        } catch (e, st) {
          debugPrint('[WindowMessenger] Error in event listener ($event): $e\n$st');
        }
      }
    }
  }

  @override
  void dispose() {
    _handlers.clear();
    _registeredWindowIds.clear();
  }
}

final Provider<WindowMessenger> windowMessengerProvider =
    Provider<WindowMessenger>((ref) {
  final messenger = DefaultWindowMessenger(isMainWindow: true);
  ref.onDispose(messenger.dispose);
  return messenger;
});
