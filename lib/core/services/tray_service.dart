import 'dart:async';
import 'dart:io' show Platform, exit;
import 'package:flutter/foundation.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore_for_file: deprecated_member_use
import 'package:tray_manager/legacy.dart';

import '../../app/app_navigation.dart';
import '../widgets/desktop_tray_message_box.dart';
import 'tray_badge_generator.dart';
import 'window_service.dart';
import '../platform/windows/windows_window_adapter.dart';

/// 统一跨平台系统托盘服务抽象 (TrayService Facade)
///
/// 核心契约：
/// 1. 桌面端（Windows / macOS / Linux）：常驻系统托盘，支持左键展开聚合浮窗/激活主窗口、右键上下文菜单；
/// 2. 未读提醒：动态绘制托盘角标数字，未读时提示并更新托盘 Tooltip 与角标提示；
/// 3. 支持呼吸闪烁 (Blinking) 与一键已读回调；
/// 4. 非桌面端（Android / iOS / Web）：安全无操作 (no-op)，防止跨平台崩溃。
abstract class TrayService {
  /// 初始化托盘图标与右键菜单
  Future<void> initialize();

  /// 更新未读消息数感知并实时重绘托盘角标
  Future<void> setUnread(int unreadCount);

  /// 设置未读时是否开启托盘呼吸闪烁
  void setBlinking(bool enabled);

  /// 更新托盘上下文菜单信息（如切换后的当前身份）
  Future<void> updateContextMenu({String? currentOwnerName});

  /// 释放托盘资源
  Future<void> dispose();

  Future<void> showContextMenu();

  /// 当前运行环境是否支持系统托盘
  bool get isSupported;
}

class DesktopTrayService with TrayListener implements TrayService {
  DesktopTrayService({required this.windowService, this.onOpenFlyout});

  final WindowService windowService;
  final VoidCallback? onOpenFlyout;

  bool _initialized = false;
  Object? _lastError;
  Future<void> _updates = Future<void>.value();
  Future<void> _enqueue(Future<void> Function() update) {
    _updates = _updates
        .then((_) async {
          if (_initialized) await update();
        })
        .catchError((Object error) {
          _lastError = error;
          debugPrint(
            '[DesktopTrayService] update failed: ${error.runtimeType}',
          );
        });
    return _updates;
  }

  int _unreadCount = 0;
  String? _currentOwnerName;
  bool _isBlinkingEnabled = true;
  Timer? _blinkTimer;
  bool _isBlinkDimmed = false;

  @override
  bool get isSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  @override
  Future<void> initialize() async {
    if (!isSupported || _initialized) return;
    try {
      _lastError = null;
      if (WindowsWindowAdapter.isWindows) {
        await WindowsWindowAdapter.setupCustomTitleBar();
        WindowsWindowAdapter.onTrayEvent = (event) {
          if (event == 'left') onTrayIconMouseDown();
          if (event == 'show') windowService.bringToFront('main');
          if (event == 'unread') onTrayIconMouseDown();
          if (event == 'exit') {
            unawaited(dispose());
            exit(0);
          }
        };
        await WindowsWindowAdapter.initializeTray();
      } else {
        trayManager.addListener(this);
        await trayManager.setIcon(_getDefaultIconPath());
        await trayManager.setToolTip('Goto IM 跨平台即时通讯');
      }
      await _buildMenu();
      _initialized = true;
      await _enqueue(() async {
        await _buildMenu();
        await _applyIcon();
        if (_unreadCount > 0 && _isBlinkingEnabled) _startBlinking();
      });
      debugPrint('[DesktopTrayService] Initialized system tray successfully.');
    } catch (e, st) {
      _lastError = e;
      _initialized = false;
      debugPrint(
        '[DesktopTrayService] Failed to initialize tray: ${e.runtimeType}\n$st',
      );
    }
  }

  String _getDefaultIconPath() {
    return Platform.isWindows
        ? 'assets/images/app_icon.ico'
        : 'assets/images/splash_logo.png';
  }

  Future<void> _buildMenu() async {
    if (!isSupported) return;
    if (WindowsWindowAdapter.isWindows) {
      await WindowsWindowAdapter.updateTray({
        'owner': _currentOwnerName ?? '',
        'unread': _unreadCount,
        'tooltip':
            _unreadCount > 0
                ? 'Goto IM ($_unreadCount条新消息)'
                : 'Goto IM 跨平台即时通讯',
      });
      return;
    }
    final ownerLabel =
        _currentOwnerName != null && _currentOwnerName!.isNotEmpty
            ? '当前身份: $_currentOwnerName'
            : 'Goto IM 聊天';

    final items = <MenuItem>[
      MenuItem(key: 'show_app', label: '打开 Goto IM'),
      if (_unreadCount > 0)
        MenuItem(key: 'open_unread_flyout', label: '查看未读消息 ($_unreadCount)'),
      MenuItem.separator(),
      MenuItem(key: 'current_owner', label: ownerLabel, disabled: true),
      MenuItem.separator(),
      MenuItem(key: 'exit_app', label: '退出应用'),
    ];

    final menu = Menu(items: items);
    await trayManager.setContextMenu(menu);
  }

  @override
  Future<void> setUnread(int unreadCount) {
    final count = unreadCount < 0 ? 0 : unreadCount;
    if (!isSupported) return _updates;
    if (!_initialized) {
      _unreadCount = count;
      return _updates;
    }
    if (_unreadCount == count) return _updates;
    _unreadCount = count;
    _stopBlinking();
    return _enqueue(() async {
      // Coalesce notifications queued before the platform finishes a frame.
      if (count != _unreadCount) return;
      if (!WindowsWindowAdapter.isWindows) {
        await trayManager.setToolTip(
          count > 0 ? 'Goto IM ($count条新消息)' : 'Goto IM 跨平台即时通讯',
        );
      }
      await _buildMenu();
      await _applyIcon();
      if (_unreadCount > 0 && _isBlinkingEnabled) _startBlinking();
    });
  }

  Future<void> _applyIcon() async {
    final count = _unreadCount;
    final dimmed = _isBlinkDimmed;
    final path =
        count > 0
            ? await TrayBadgeGenerator.generateBadgeIconPath(
              unreadCount: count,
              isDimmed: dimmed,
            )
            : (WindowsWindowAdapter.isWindows ? '' : _getDefaultIconPath());
    if (path != null &&
        count == _unreadCount &&
        dimmed == _isBlinkDimmed &&
        _initialized) {
      if (WindowsWindowAdapter.isWindows) {
        await WindowsWindowAdapter.updateTray({'iconPath': path});
      } else {
        await trayManager.setIcon(path);
      }
    }
  }

  @override
  void setBlinking(bool enabled) {
    _isBlinkingEnabled = enabled;
    _stopBlinking();
    unawaited(_enqueue(_applyIcon));
    if (enabled && _unreadCount > 0) _startBlinking();
  }

  void _startBlinking() {
    _blinkTimer?.cancel();
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      if (_unreadCount <= 0 || !_isBlinkingEnabled) {
        _stopBlinking();
        return;
      }
      unawaited(
        _enqueue(() async {
          _isBlinkDimmed = !_isBlinkDimmed;
          await _applyIcon();
        }),
      );
    });
  }

  void _stopBlinking() {
    _blinkTimer?.cancel();
    _blinkTimer = null;
    _isBlinkDimmed = false;
  }

  @override
  Future<void> updateContextMenu({String? currentOwnerName}) async {
    if (!isSupported) return;
    _currentOwnerName = currentOwnerName;
    if (!_initialized) return;
    try {
      await _buildMenu();
    } catch (e) {
      debugPrint('[DesktopTrayService] updateContextMenu failed: $e');
    }
  }

  @override
  void onTrayIconMouseDown() {
    // 左键点击托盘图标：
    // 若有新消息，唤起按聊天对象分组的无边框未读聚合浮窗；
    // 若无新消息，唤起并激活主窗口
    if (_unreadCount > 0) {
      if (onOpenFlyout != null) {
        onOpenFlyout!();
        return;
      }
      final context = rootNavigatorKey.currentContext;
      if (context != null && context.mounted) {
        DesktopTrayMessageBox.show(context);
        return;
      }
    }
    windowService.bringToFront('main');
  }

  @override
  void onTrayIconRightMouseDown() {
    // 右键点击托盘图标：弹出上下文菜单
    unawaited(showContextMenu());
  }

  @override
  Future<void> showContextMenu() async {
    if (!_initialized) return;
    if (WindowsWindowAdapter.isWindows) {
      await WindowsWindowAdapter.showTrayMenu();
    } else {
      await trayManager.popUpContextMenu();
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show_app') {
      windowService.bringToFront('main');
    } else if (menuItem.key == 'open_unread_flyout') {
      final context = rootNavigatorKey.currentContext;
      if (context != null && context.mounted) {
        DesktopTrayMessageBox.show(context);
      }
    } else if (menuItem.key == 'exit_app') {
      dispose();
      exit(0);
    }
  }

  @override
  Future<void> dispose() async {
    if (!isSupported || !_initialized) return;
    try {
      _stopBlinking();
      _initialized = false;
      await _updates;
      if (WindowsWindowAdapter.isWindows) {
        WindowsWindowAdapter.onTrayEvent = null;
        await WindowsWindowAdapter.destroyTray();
      } else {
        trayManager.removeListener(this);
        await trayManager.destroy();
      }
    } catch (e) {
      debugPrint('[DesktopTrayService] dispose failed: $e');
    }
  }
}

/// Child engines forward tray commands to the single tray owned by the main engine.
class SubWindowTrayService implements TrayService {
  const SubWindowTrayService();
  static const _channel = WindowMethodChannel(
    'gotoim/ipc_to_main',
    mode: ChannelMode.bidirectional,
  );
  @override
  bool get isSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
  @override
  Future<void> initialize() async {}
  @override
  Future<void> dispose() async {}
  @override
  Future<void> setUnread(int unreadCount) async {
    await _channel.invokeMethod('tray_command', {'unread': unreadCount});
  }

  @override
  void setBlinking(bool enabled) {
    unawaited(
      _channel
          .invokeMethod('tray_command', {'blinking': enabled})
          .then<void>((_) {})
          .catchError((Object error) {
            debugPrint('[SubWindowTrayService] command failed: $error');
          }),
    );
  }

  @override
  Future<void> showContextMenu() async {
    await _channel.invokeMethod('tray_command', {'showMenu': true});
  }

  @override
  Future<void> updateContextMenu({String? currentOwnerName}) async {
    await _channel.invokeMethod('tray_command', {
      'ownerName': currentOwnerName,
    });
  }
}

/// 非桌面端安全空实现
class NoopTrayService implements TrayService {
  const NoopTrayService();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> setUnread(int unreadCount) async {}

  @override
  void setBlinking(bool enabled) {}

  @override
  Future<void> updateContextMenu({String? currentOwnerName}) async {}

  @override
  Future<void> dispose() async {}

  @override
  bool get isSupported => false;
  @override
  Future<void> showContextMenu() async {}
}

final Provider<TrayService> trayServiceProvider = Provider<TrayService>((ref) {
  final isDesktop =
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
  if (!isDesktop) {
    return const NoopTrayService();
  }
  final windowService = ref.watch(windowServiceProvider);
  final tray = DesktopTrayService(windowService: windowService);
  // Wire the existing instance in one direction. Reading trayServiceProvider
  // from windowServiceProvider's IPC handler creates a Riverpod dependency cycle.
  if (windowService is DefaultWindowService) {
    windowService.trayCommand = (arguments) async {
      await tray.initialize();
      if (!tray._initialized) throw StateError('主窗口托盘初始化失败');
      tray._lastError = null;
      if (arguments['showMenu'] == true) await tray.showContextMenu();
      if (arguments['unread'] is num) {
        await tray.setUnread((arguments['unread'] as num).toInt());
      }
      if (arguments['blinking'] is bool) {
        tray.setBlinking(arguments['blinking'] as bool);
      }
      if (arguments.containsKey('ownerName')) {
        await tray.updateContextMenu(
          currentOwnerName: arguments['ownerName'] as String?,
        );
      }
      if (tray._lastError != null) throw StateError('主窗口托盘更新失败');
    };
  }
  ref.onDispose(() {
    if (windowService is DefaultWindowService) windowService.trayCommand = null;
    unawaited(tray.dispose());
  });
  return tray;
});
