import 'dart:async';
import 'dart:io' show Platform, exit;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';

import 'window_service.dart';

/// 统一跨平台系统托盘服务抽象 (TrayService Facade)
///
/// 核心契约：
/// 1. 桌面端（Windows / macOS / Linux）：常驻系统托盘，支持左键激活主窗口、右键上下文菜单；
/// 2. 未读提醒：新消息未读数感知，未读时提示并更新托盘 Tooltip 与角标提示；
/// 3. 非桌面端（Android / iOS / Web）：安全无操作 (no-op)，防止跨平台崩溃。
abstract class TrayService {
  /// 初始化托盘图标与右键菜单
  Future<void> initialize();

  /// 更新未读消息数感知
  Future<void> setUnread(int unreadCount);

  /// 更新托盘上下文菜单信息（如切换后的当前身份）
  Future<void> updateContextMenu({String? currentOwnerName});

  /// 释放托盘资源
  Future<void> dispose();

  /// 当前运行环境是否支持系统托盘
  bool get isSupported;
}

class DesktopTrayService with TrayListener implements TrayService {
  DesktopTrayService({required this.windowService});

  final WindowService windowService;
  bool _initialized = false;
  int _unreadCount = 0;
  String? _currentOwnerName;

  @override
  bool get isSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  @override
  Future<void> initialize() async {
    if (!isSupported || _initialized) return;
    try {
      trayManager.addListener(this);

      // Windows/macOS 图标配置
      final iconPath =
          Platform.isWindows
              ? 'assets/images/app_icon.ico'
              : 'assets/images/splash_logo.png';

      await trayManager.setIcon(iconPath);
      await trayManager.setToolTip('Goto IM 跨平台即时通讯');
      await _buildMenu();
      _initialized = true;
      debugPrint('[DesktopTrayService] Initialized system tray successfully.');
    } catch (e, st) {
      debugPrint('[DesktopTrayService] Failed to initialize tray: $e\n$st');
    }
  }

  Future<void> _buildMenu() async {
    if (!isSupported) return;
    final ownerLabel =
        _currentOwnerName != null && _currentOwnerName!.isNotEmpty
            ? '当前身份: $_currentOwnerName'
            : 'Goto IM 聊天';

    final menu = Menu(
      items: [
        MenuItem(
          key: 'show_app',
          label: '显示 Goto IM',
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'current_owner',
          label: ownerLabel,
          disabled: true,
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'exit_app',
          label: '退出应用',
        ),
      ],
    );
    await trayManager.setContextMenu(menu);
  }

  @override
  Future<void> setUnread(int unreadCount) async {
    if (!isSupported || !_initialized) return;
    if (_unreadCount == unreadCount) return;
    _unreadCount = unreadCount;
    try {
      final tooltip =
          unreadCount > 0
              ? 'Goto IM ($unreadCount条新消息)'
              : 'Goto IM 跨平台即时通讯';
      await trayManager.setToolTip(tooltip);
    } catch (e) {
      debugPrint('[DesktopTrayService] setUnread failed: $e');
    }
  }

  @override
  Future<void> updateContextMenu({String? currentOwnerName}) async {
    if (!isSupported || !_initialized) return;
    _currentOwnerName = currentOwnerName;
    try {
      await _buildMenu();
    } catch (e) {
      debugPrint('[DesktopTrayService] updateContextMenu failed: $e');
    }
  }

  @override
  void onTrayIconMouseDown() {
    // 左键点击托盘图标：唤起并激活主窗口
    windowService.bringToFront('main');
  }

  @override
  void onTrayIconRightMouseDown() {
    // 右键点击托盘图标：弹出菜单
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show_app') {
      windowService.bringToFront('main');
    } else if (menuItem.key == 'exit_app') {
      dispose();
      exit(0);
    }
  }

  @override
  Future<void> dispose() async {
    if (!isSupported || !_initialized) return;
    try {
      trayManager.removeListener(this);
      await trayManager.destroy();
      _initialized = false;
    } catch (e) {
      debugPrint('[DesktopTrayService] dispose failed: $e');
    }
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
  Future<void> updateContextMenu({String? currentOwnerName}) async {}

  @override
  Future<void> dispose() async {}

  @override
  bool get isSupported => false;
}

final Provider<TrayService> trayServiceProvider = Provider<TrayService>((ref) {
  final isDesktop =
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
  if (!isDesktop) {
    return const NoopTrayService();
  }
  final windowService = ref.watch(windowServiceProvider);
  final tray = DesktopTrayService(windowService: windowService);
  ref.onDispose(tray.dispose);
  return tray;
});
