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
            icon: Icons.perm_media_outlined,
            title: '媒体与文件测试',
            subtitle: '相册、拍照、视频、缩略图、压缩、录音、图片识码与另存为',
            onTap: () => context.push('/diagnostics/media'),
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
