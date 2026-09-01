import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class DiagnosticsHomePage extends StatelessWidget {
  const DiagnosticsHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(body: Center(child: Text('开发诊断仅在 Debug 模式可用。')));
    }
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回首页',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        title: const Text('开发诊断中心'),
      ),
      body: ListView(
        children: [
          _Item(
            icon: Icons.lan_outlined,
            title: 'Remote DevTools / AI 日志',
            subtitle: '真机局域网日志、WebSocket 控制台、脱敏日志与异常源码定位',
            onTap: () => context.push('/diagnostics/remote-devtools'),
          ),
          _Item(
            icon: Icons.key_outlined,
            title: '认证与敏感凭据',
            subtitle: '登录、Token、检查、撤销、退出与复制',
            onTap: () => context.push('/diagnostics/auth'),
          ),
          _Item(
            icon: Icons.api_outlined,
            title: 'API 接口测试',
            subtitle: '用户、好友、消息等 HTTP API',
            onTap: () => context.push('/diagnostics/api'),
          ),
          _Item(
            icon: Icons.hub_outlined,
            title: 'SignalR 测试',
            subtitle: 'Chat Hub、连接详情、事件与 payload',
            onTap: () => context.push('/diagnostics/signalr'),
          ),
          _Item(
            icon: Icons.notifications_active_outlined,
            title: '本地通知测试',
            subtitle: '权限、渠道、通知内容、点击 Payload 与取消',
            onTap: () => context.push('/diagnostics/notifications'),
          ),
          _Item(
            icon: Icons.qr_code_scanner_outlined,
            title: '统一扫码测试',
            subtitle: '相机、扫描框动画、闪光灯、相册与上传图片识别',
            onTap: () => context.push('/diagnostics/scan-code'),
          ),
          _Item(
            icon: Icons.phone_android_outlined,
            title: '客户端能力中心',
            subtitle: '系统、设备、网络、剪贴板与文件选择的分级调用和返回结果',
            onTap: () => context.push('/diagnostics/capabilities'),
          ),
          _Item(
            icon: Icons.devices_outlined,
            title: '设备注册与信息采集',
            subtitle: 'client_credentials、实际请求、完整 Payload、返回结果与异常',
            onTap: () => context.push('/diagnostics/device-registration'),
          ),
          _Item(
            icon: Icons.javascript_outlined,
            title: 'JS Bridge 测试',
            subtitle: 'JSON 请求/响应、能力 API、上传任务、订阅与事件',
            onTap: () => context.push('/diagnostics/js-bridge'),
          ),
          _Item(
            icon: Icons.web_outlined,
            title: 'JS Bridge Harness',
            subtitle: '真实双向通道、上传闭环与 Flutter 主动调用回执',
            onTap: () => context.push('/diagnostics/js-bridge-harness'),
          ),
          _Item(
            icon: Icons.storage_outlined,
            title: '统一数据库测试',
            subtitle: 'SQLite schema 迁移、表信息、CRUD、创建/删除测试表',
            onTap: () => context.push('/diagnostics/database'),
          ),
          _Item(
            icon: Icons.forum_outlined,
            title: '消息列表数据流',
            subtitle: 'Owner、本地好友分页、线上补页、changes 增量与游标',
            onTap: () => context.push('/diagnostics/session-list'),
          ),
          _Item(
            icon: Icons.chat_bubble_outline,
            title: '聊天窗口',
            subtitle: '本地消息、历史分页与文本发送',
            onTap: () => context.push('/diagnostics/chat'),
          ),
          _Item(
            icon: Icons.fullscreen_outlined,
            title: 'AdaptivePage 半屏 / 普通页',
            subtitle: '半屏/完整页转换、状态保留、拖拽长列表与键盘避让',
            onTap: () => context.push('/diagnostics/adaptive-page'),
          ),
          _Item(
            icon: Icons.keyboard_arrow_up_outlined,
            title: '半屏页组件',
            subtitle: '高度、键盘避让、拖拽、关闭、圆角与实际返回结果',
            onTap: () => context.push('/diagnostics/half-page-sheet'),
          ),
          _Item(
            icon: Icons.notifications_active_outlined,
            title: 'Toast 提示与反馈',
            subtitle: '顶部/居中/底部悬浮位置、振动反馈、声音提示与全局配置',
            onTap: () => context.push('/diagnostics/toast'),
          ),
          _Item(
            icon: Icons.chat_outlined,
            title: 'Modal 对话框全功能',
            subtitle: 'Alert 告警、Confirm 确认、Prompt 输入、ActionSheet 菜单与异步拦截',
            onTap: () => context.push('/diagnostics/modal'),
          ),
          _Item(
            icon: Icons.bubble_chart_outlined,
            title: '聊天气泡参数',
            subtitle: '实时调节反角 S 曲线尾巴并生成 JSON 参数',
            onTap: () => context.push('/diagnostics/chat-bubble'),
          ),
          _Item(
            icon: Icons.perm_media_outlined,
            title: '媒体与文件测试',
            subtitle: '相册、拍照、视频、缩略图、压缩、录音、图片识码与另存为',
            onTap: () => context.push('/diagnostics/media'),
          ),
          _Item(
            icon: Icons.fullscreen,
            title: '统一媒体预览',
            subtitle: '图片缩放、左右切换、下拉关闭与视频播放器生命周期',
            onTap: () => context.push('/diagnostics/media-preview'),
          ),
          _Item(
            icon: Icons.account_circle_outlined,
            title: '头像与裁剪',
            subtitle: '圆/方显示、1:1 裁剪、上传头像、缓存失效与当前身份刷新',
            onTap: () => context.push('/settings/avatar'),
          ),
          _Item(
            icon: Icons.picture_in_picture_alt_outlined,
            title: 'Floating Window 浮动窗口',
            subtitle: '多窗口、拖动、吸边、键盘避让、跨路由与窗口缩放',
            onTap: () => context.push('/diagnostics/floating-window'),
          ),
          _Item(
            icon: Icons.web_asset_outlined,
            title: 'WebView Session',
            subtitle: '真实 URL、历史、Cookie、导航、JSBridge 状态与平台验收清单',
            onTap: () => context.push('/diagnostics/webview-session'),
          ),
          _Item(
            icon: Icons.tab_outlined,
            title: '应用级任务栈',
            subtitle: '独立 Task 创建/复用、工作台动态应用、Android Document Task',
            onTap: () => context.push('/diagnostics/app-task'),
          ),
          _Item(
            icon: Icons.link_outlined,
            title: 'Deep Link / App Links',
            subtitle: 'URI 解析、聊天/用户/群组/扫码/工作台/OAuth 协议、执行与事件日志',
            onTap: () => context.push('/diagnostics/deep-link'),
          ),
          _Item(
            icon: Icons.folder_shared_outlined,
            title: '局域网文件管理',
            subtitle: '本地 HTTP 服务、验证码认证、浏览器终端、分片上传与 Range 下载',
            onTap: () => context.push('/diagnostics/local-file-server'),
          ),
          _Item(
            icon: Icons.palette_outlined,
            title: '主题与暗黑模式',
            subtitle: 'Material 3 调色板、语义 Token、字阶、组件展示与实时切换',
            onTap: () => context.push('/diagnostics/theme'),
          ),
          _Item(
            icon: Icons.developer_mode_outlined,
            title: 'Native / Device 设备能力',
            subtitle: '截屏监听、振动反馈、系统主题、内存告警、加速度计、陀螺仪、距离传感器、亮度与电量',
            onTap: () => context.push('/diagnostics/native'),
          ),
        ],
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}
