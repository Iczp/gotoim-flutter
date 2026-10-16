import 'dart:async';
import 'dart:io' show Platform, exit;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore_for_file: deprecated_member_use
import 'package:tray_manager/legacy.dart';

import '../../app/app_navigation.dart';
import '../widgets/desktop_tray_message_box.dart';
import 'tray_badge_generator.dart';
import 'window_service.dart';

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

  /// 当前运行环境是否支持系统托盘
  bool get isSupported;
}

class DesktopTrayService with TrayListener implements TrayService {
  DesktopTrayService({
    required this.windowService,
    this.onOpenFlyout,
  });

  final WindowService windowService;
  final VoidCallback? onOpenFlyout;

  bool _initialized = false;
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
      trayManager.addListener(this);

      // 默认基础图标配置
      final defaultIconPath = _getDefaultIconPath();
      await trayManager.setIcon(defaultIconPath);
      await trayManager.setToolTip('Goto IM 跨平台即时通讯');
      await _buildMenu();
      _initialized = true;
      debugPrint('[DesktopTrayService] Initialized system tray successfully.');
    } catch (e, st) {
      debugPrint('[DesktopTrayService] Failed to initialize tray: $e\n$st');
    }
  }

  String _getDefaultIconPath() {
    return Platform.isWindows
        ? 'assets/images/app_icon.ico'
        : 'assets/images/splash_logo.png';
  }

  Future<void> _buildMenu() async {
    if (!isSupported) return;
    final ownerLabel =
        _currentOwnerName != null && _currentOwnerName!.isNotEmpty
            ? '当前身份: $_currentOwnerName'
            : 'Goto IM 聊天';

    final items = <MenuItem>[
      MenuItem(
        key: 'show_app',
        label: '打开 Goto IM',
      ),
      if (_unreadCount > 0)
        MenuItem(
          key: 'open_unread_flyout',
          label: '查看未读消息 ($_unreadCount)',
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
    ];

    final menu = Menu(items: items);
    await trayManager.setContextMenu(menu);
  }

  @override
  Future<void> setUnread(int unreadCount) async {
    if (!isSupported || !_initialized) return;
    if (_unreadCount == unreadCount) return;
    _unreadCount = unreadCount;

    try {
      final tooltip = unreadCount > 0
          ? 'Goto IM ($unreadCount条新消息)'
          : 'Goto IM 跨平台即时通讯';
      await trayManager.setToolTip(tooltip);
      await _buildMenu();

      // 动态更新或绘制带有角标数字的托盘图标
      if (unreadCount > 0) {
        final badgePath = await TrayBadgeGenerator.generateBadgeIconPath(
          unreadCount: unreadCount,
        );
        if (badgePath != null) {
          await trayManager.setIcon(badgePath);
        }
        if (_isBlinkingEnabled) {
          _startBlinking();
        }
      } else {
        _stopBlinking();
        await trayManager.setIcon(_getDefaultIconPath());
      }
    } catch (e) {
      debugPrint('[DesktopTrayService] setUnread failed: $e');
    }
  }

  @override
  void setBlinking(bool enabled) {
    _isBlinkingEnabled = enabled;
    if (!enabled) {
      _stopBlinking();
      if (_unreadCount > 0) {
        TrayBadgeGenerator.generateBadgeIconPath(unreadCount: _unreadCount)
            .then((path) {
          if (path != null) trayManager.setIcon(path);
        });
      }
    } else if (_unreadCount > 0) {
      _startBlinking();
    }
  }

  void _startBlinking() {
    _blinkTimer?.cancel();
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 800), (_) async {
      if (_unreadCount <= 0 || !_isBlinkingEnabled) {
        _stopBlinking();
        return;
      }
      _isBlinkDimmed = !_isBlinkDimmed;
      final iconPath = await TrayBadgeGenerator.generateBadgeIconPath(
        unreadCount: _unreadCount,
        isDimmed: _isBlinkDimmed,
      );
      if (iconPath != null) {
        await trayManager.setIcon(iconPath);
      }
    });
  }

  void _stopBlinking() {
    _blinkTimer?.cancel();
    _blinkTimer = null;
    _isBlinkDimmed = false;
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
    trayManager.popUpContextMenu();
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
  void setBlinking(bool enabled) {}

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
