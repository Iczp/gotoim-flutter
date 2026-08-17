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
