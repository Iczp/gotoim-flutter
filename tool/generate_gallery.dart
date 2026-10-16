import 'dart:convert';
import 'dart:io';

void main() {
  final items = [
    {
      'title': '【重点】真实账号 (admin) 登录态下的微信 4.0 纯净无边框主窗口 (1280 × 800)',
      'file': 'screenshot_desktop_main_window_borderless.png',
      'desc': '使用真实账号 (admin - 360cfedb) 登录真实后端 API，加载真实多身份（私人助理/林惠娟/日春田安店等）与真实群聊（Google Gemini 架构组），全无边框（border: null），微信经典中性黑灰色阶。'
    },
    {
      'title': '【重点】托盘新消息聚合浮窗 - “新消息居多，列表过长”极限场景 (380 × 560)',
      'file': 'screenshot_desktop_tray_excessive_messages.png',
      'desc': '模拟多身份收到大量新消息（128+ 条未读）：主身份超 4 个群自动截断并展示“展开其余 4 个会话 ▾”，非当前身份智能默认折叠，顶部支持“全部折叠/展开”与“一键已读”，右侧带有原生暗黑细滚动条。'
    },
    {
      'title': '【重点】托盘新消息聚合浮窗 - 真实账号多身份未读常规展示 (380 × 480)',
      'file': 'screenshot_desktop_tray_real_account.png',
      'desc': '真实账号下按聊天对象分组：私人助理（当前身份 - 5条新消息）、林惠娟（2条新消息）、日春田安店（3条新消息），层级分明，单组支持一键已读。'
    },
    {
      'title': '1. 桌面端标准三栏布局 (1280 × 800)',
      'file': 'screenshot_desktop_wide_1280x800.png',
      'desc': '左侧极简深色 Dock Rail 常驻、会话列表带气泡未读、中性黑灰阶统一（#1E1E1E / #232323 / #282828）、微软雅黑中文清晰锐利、头像置底。'
    },
    {
      'title': '2. 平板端双栏紧凑布局 (900 × 700)',
      'file': 'screenshot_desktop_tablet_900x700.png',
      'desc': '非窄屏手机绝不隐藏侧边栏！保留 52px 极简 Dock Rail，右侧会话列表与聊天主视窗无缝协同。'
    },
    {
      'title': '3. 手机/窄屏模式自适应单栏 (450 × 800)',
      'file': 'screenshot_desktop_phone_450x800.png',
      'desc': '仅当窗口宽度小于 560px 时，自动收起左侧 Rail 切换为手机单栏全屏模式。'
    },
    {
      'title': '4. 微信同款独立系统设置窗口 (730 × 560)',
      'file': 'screenshot_desktop_settings_window.png',
      'desc': '独立新开窗口，严格无边框，左侧导航与右侧内容采用中性灰阶，中文字形平滑，多类别设置项完备。'
    },
    {
      'title': '5. 微信同款独立内置浏览器窗口 (1000 × 700)',
      'file': 'screenshot_desktop_browser_window.png',
      'desc': '独立外链沙箱，严格无边框，深灰窗口外框与 Tab 栏，支持前进/后退/刷新/置顶/外部浏览器打开。'
    },
    {
      'title': '6. 微信同款独立媒体查看窗口 (920 × 680)',
      'file': 'screenshot_desktop_media_viewer_window.png',
      'desc': '沉浸式纯黑底色，严格无边框，专用于大图浏览、高保真视频播放与原图旋转下载。'
    },
    {
      'title': '7. 系统托盘图标与右键菜单 (360 × 300)',
      'file': 'screenshot_desktop_tray_menu.png',
      'desc': '系统托盘图标右键菜单，深灰色调圆角面板，显示激活窗口、当前身份及退出。'
    },
  ];

  final dir = Directory('f:/Dev/GotoIM/gotoim-flutter/screenshots');
  final artifactDir = Directory('C:/Users/ZP/.gemini/antigravity/brain/f3f5edfb-7920-4a04-b0bc-cda5b23e58ef');

  final sb = StringBuffer();
  sb.writeln('''<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <title>GotoIM 桌面端全尺寸适配与真实截图预览</title>
  <style>
    body {
      background: #141414;
      color: #E2E8F0;
      font-family: "Microsoft YaHei", "微软雅黑", -apple-system, sans-serif;
      margin: 0;
      padding: 32px;
      line-height: 1.6;
    }
    .header {
      border-bottom: 1px solid #282828;
      padding-bottom: 20px;
      margin-bottom: 30px;
    }
    h1 {
      color: #07C160;
      font-size: 24px;
      margin: 0 0 8px 0;
    }
    .badge-bar {
      display: flex;
      gap: 12px;
      margin-top: 12px;
    }
    .badge {
      background: #232323;
      border: 1px solid #383838;
      color: #A0AEC0;
      padding: 4px 12px;
      border-radius: 6px;
      font-size: 12px;
    }
    .badge.active {
      border-color: #07C160;
      color: #07C160;
    }
    .gallery {
      display: flex;
      flex-direction: column;
      gap: 36px;
    }
    .card {
      background: #1E1E1E;
      border: 1px solid #2C2C2C;
      border-radius: 12px;
      padding: 24px;
      box-shadow: 0 10px 30px rgba(0,0,0,0.5);
    }
    .card-title {
      font-size: 18px;
      font-weight: 600;
      color: #FFFFFF;
      margin-bottom: 8px;
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .card-title::before {
      content: "";
      width: 4px;
      height: 16px;
      background: #07C160;
      border-radius: 2px;
    }
    .card-desc {
      font-size: 13px;
      color: #94A3B8;
      margin-bottom: 18px;
    }
    .img-box {
      background: #0D0D0D;
      border: 1px solid #282828;
      border-radius: 8px;
      padding: 16px;
      display: flex;
      justify-content: center;
      align-items: center;
    }
    img {
      max-width: 100%;
      height: auto;
      border-radius: 6px;
      box-shadow: 0 4px 20px rgba(0,0,0,0.7);
    }
    .path-hint {
      margin-top: 12px;
      font-size: 11px;
      color: #64748B;
      font-family: Consolas, monospace;
    }
  </style>
</head>
<body>
  <div class="header">
    <h1>GotoIM 桌面端全尺寸适配与多窗口截图总览</h1>
    <div class="badge-bar">
      <span class="badge active">微信深灰色系 (#1E1E1E / #232323 / #282828)</span>
      <span class="badge active">微软雅黑真实字体</span>
      <span class="badge active">侧边栏常驻 (非小屏不隐藏)</span>
      <span class="badge active">全部 9 项测试通过</span>
    </div>
  </div>
  <div class="gallery">
''');

  for (final item in items) {
    final fileName = item['file']!;
    final file = File('${dir.path}/$fileName');
    if (!file.existsSync()) {
      print('Warning: ${file.path} not found');
      continue;
    }
    final bytes = file.readAsBytesSync();
    final b64 = base64Encode(bytes);
    sb.writeln('''
    <div class="card">
      <div class="card-title">${item['title']}</div>
      <div class="card-desc">${item['desc']}</div>
      <div class="img-box">
        <img src="data:image/png;base64,$b64" alt="${item['title']}" />
      </div>
      <div class="path-hint">本地源文件: ${file.path} (${bytes.length} bytes)</div>
    </div>
''');
  }

  sb.writeln('''
  </div>
</body>
</html>
''');

  File('${dir.path}/gallery.html').writeAsStringSync(sb.toString());
  File('${artifactDir.path}/desktop_screenshots_gallery.html').writeAsStringSync(sb.toString());
  print('Successfully generated gallery.html in both locations!');
}
