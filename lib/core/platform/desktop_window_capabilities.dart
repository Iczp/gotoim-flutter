import 'package:flutter/foundation.dart';

/// 桌面窗口跨平台具体能力集合与诊断状态
@immutable
class DesktopWindowCapabilities {
  const DesktopWindowCapabilities({
    required this.platformName,
    required this.supportsMultipleWindows,
    required this.supportsWindowDocking,
    required this.supportsNativeProfileFlyout,
    required this.supportsNativeFirstFrameAck,
    required this.supportsNativeScreenCapture,
    required this.supportsBuiltinAnnotation,
    required this.supportsAlwaysOnTop,
    required this.supportsVideoPlayback,
    required this.supportsCustomTitleBar,
    required this.supportsTray,
    this.statusReasons = const {},
  });

  /// 运行平台名称（Windows / macOS / Linux / Web / Mobile）
  final String platformName;

  /// 是否支持独立子引擎多窗口 (desktop_multi_window)
  final bool supportsMultipleWindows;

  /// 是否支持原生窗口吸附 (嵌入父视窗同时保留同一 Flutter 引擎与原生宿主)
  final bool supportsWindowDocking;

  /// 是否支持无夺焦独立悬浮资料卡定位及跨窗口悬停保持
  final bool supportsNativeProfileFlyout;

  /// 是否支持原生首帧绘制确认 (等待底层操作系统窗口真正渲染完成才呈现)
  final bool supportsNativeFirstFrameAck;

  /// 是否支持原生系统屏幕底图捕获
  final bool supportsNativeScreenCapture;

  /// 是否支持内置截图标注工作台 (8 锚点选区、涂鸦标注)
  final bool supportsBuiltinAnnotation;

  /// 是否支持窗口置顶 (pin)
  final bool supportsAlwaysOnTop;

  /// 是否已接入并支持独立视窗视频流播放插件
  final bool supportsVideoPlayback;

  /// 是否支持自定义沉浸式标题栏及原生拖拽
  final bool supportsCustomTitleBar;

  /// 是否支持系统托盘及托盘未读消息
  final bool supportsTray;

  /// 各能力的限制、环境依赖或待补齐原因说明
  final Map<String, String> statusReasons;

  /// Windows 平台基线能力
  factory DesktopWindowCapabilities.windows() {
    return const DesktopWindowCapabilities(
      platformName: 'Windows',
      supportsMultipleWindows: true,
      supportsWindowDocking: true,
      supportsNativeProfileFlyout: true,
      supportsNativeFirstFrameAck: true,
      supportsNativeScreenCapture: true,
      supportsBuiltinAnnotation: true,
      supportsAlwaysOnTop: true,
      supportsVideoPlayback: true,
      supportsCustomTitleBar: true,
      supportsTray: true,
      statusReasons: {
        'supportsWindowDocking': 'Windows 原生已验证 (owned 无边框顶层窗口 + HWND 动态跟随)',
        'supportsVideoPlayback': 'Windows 已接入 video_player_win 原生解码',
        'supportsNativeScreenCapture': 'Windows 已接入 Win32 GDI 虚拟桌面瞬间位图截取',
      },
    );
  }

  /// Only expose complete native protocols. Basic AppKit controls are wired;
  /// docking, hover tracking and actual raster acknowledgement still need work.
  factory DesktopWindowCapabilities.macos() => const DesktopWindowCapabilities(
    platformName: 'macOS',
    supportsMultipleWindows: true,
    supportsWindowDocking: false,
    supportsNativeProfileFlyout: false,
    supportsNativeFirstFrameAck: false,
    supportsNativeScreenCapture: false,
    supportsBuiltinAnnotation: false,
    supportsAlwaysOnTop: true,
    supportsVideoPlayback: true,
    supportsCustomTitleBar: true,
    supportsTray: true,
    statusReasons: {
      'supportsWindowDocking': '尚缺少吸附快照恢复、布局同步与可见性协议，保留独立窗口',
      'supportsNativeProfileFlyout': '尚未实现跨窗口悬停、显示器边界与点击保留协议',
      'supportsNativeFirstFrameAck':
          'Flutter 预热可用；CATransaction.flush 不代表 Flutter 首帧已呈现',
      'supportsNativeScreenCapture': '内置捕获与权限流程未完成，使用系统 screencapture 替代路径',
      'supportsBuiltinAnnotation': '缺少可用的内置屏幕捕获及全屏选区宿主',
      'validation': 'AppKit 控制已接入，尚需 macOS 构建和真机验收',
    },
  );

  factory DesktopWindowCapabilities.linux() => const DesktopWindowCapabilities(
    platformName: 'Linux',
    supportsMultipleWindows: true,
    supportsWindowDocking: false,
    supportsNativeProfileFlyout: false,
    supportsNativeFirstFrameAck: false,
    supportsNativeScreenCapture: false,
    supportsBuiltinAnnotation: false,
    supportsAlwaysOnTop: false,
    supportsVideoPlayback: false,
    supportsCustomTitleBar: false,
    supportsTray: true,
    statusReasons: {
      'supportsMultipleWindows': '主引擎和子引擎均注册插件及窗口通道，待目标环境验收',
      'supportsWindowDocking': 'X11/Wayland 吸附协议尚未实现，保留独立窗口',
      'supportsNativeProfileFlyout': '缺少独立资料卡定位及跨窗口悬停协议',
      'supportsNativeFirstFrameAck': '主视图 first-frame 不是子引擎逐次原生绘制确认',
      'supportsNativeScreenCapture': '仅提供 gnome-screenshot 外部替代路径，依赖运行环境',
      'supportsBuiltinAnnotation': '尚未接入内置捕获与全屏选区宿主',
      'supportsVideoPlayback': '当前未接入 Linux 视频播放后端',
      'supportsTray': '依赖托盘插件和桌面环境，尚需 Linux 真机验收',
    },
  );

  /// 非桌面或降级兜底能力
  factory DesktopWindowCapabilities.fallback(String name) {
    return DesktopWindowCapabilities(
      platformName: name,
      supportsMultipleWindows: false,
      supportsWindowDocking: false,
      supportsNativeProfileFlyout: false,
      supportsNativeFirstFrameAck: false,
      supportsNativeScreenCapture: false,
      supportsBuiltinAnnotation: false,
      supportsAlwaysOnTop: false,
      supportsVideoPlayback: false,
      supportsCustomTitleBar: false,
      supportsTray: false,
      statusReasons: const {'fallback': '非桌面平台或当前运行环境不支持原生独立窗口能力'},
    );
  }

  Map<String, dynamic> toMap() => {
    'platformName': platformName,
    'supportsMultipleWindows': supportsMultipleWindows,
    'supportsWindowDocking': supportsWindowDocking,
    'supportsNativeProfileFlyout': supportsNativeProfileFlyout,
    'supportsNativeFirstFrameAck': supportsNativeFirstFrameAck,
    'supportsNativeScreenCapture': supportsNativeScreenCapture,
    'supportsBuiltinAnnotation': supportsBuiltinAnnotation,
    'supportsAlwaysOnTop': supportsAlwaysOnTop,
    'supportsVideoPlayback': supportsVideoPlayback,
    'supportsCustomTitleBar': supportsCustomTitleBar,
    'supportsTray': supportsTray,
    'statusReasons': statusReasons,
  };
}
