import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../workbench/application/webview_session.dart';

/// Reads live MiniApp WebView sessions. It never creates a PlatformView just
/// for diagnostics, which keeps this page safe on every supported platform.
class WebViewSessionDiagnosticsPage extends StatelessWidget {
  const WebViewSessionDiagnosticsPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('WebView Session 测试')),
    body: ListenableBuilder(
      listenable: WebViewSessionRegistry.shared,
      builder: (context, _) {
        final sessions = WebViewSessionRegistry.shared.sessions;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              '状态来自当前已打开的小程序 WebView。浮窗不会重挂载 PlatformView：'
              '缩小/恢复功能须在各平台原生宿主验证通过后再开启。',
            ),
            const SizedBox(height: 12),
            Text('执行状态：已读取 ${sessions.length} 个活动会话'),
            if (sessions.isEmpty) ...[
              const SizedBox(height: 8),
              const Text('暂无会话。请从工作台打开一个 Web 小程序后返回本页查看。'),
            ],
            for (final session in sessions) ...[
              const SizedBox(height: 12),
              _SessionCard(session: session),
            ],
            const SizedBox(height: 20),
            const Text('人工验收（实际设备执行，未执行项不应标记为通过）'),
            const SizedBox(height: 8),
            const _Checklist(
              'Android / iOS',
              '打开输入框并唤起键盘；拖动浮窗标题栏；缩小/恢复后确认网页、焦点与 Cookie 未丢失。',
            ),
            const _Checklist(
              'Windows / macOS',
              '验证 WebView 标题栏层级、鼠标拖动、文字输入、前进后退及窗口恢复。',
            ),
            const _Checklist(
              'JSBridge',
              '使用“JS Bridge Harness”执行真实双向请求；本页只展示 MiniApp 已实际接入的桥状态。',
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => context.push('/diagnostics/js-bridge-harness'),
              icon: const Icon(Icons.javascript),
              label: const Text('打开 JS Bridge Harness'),
            ),
          ],
        );
      },
    ),
  );
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session});

  final WebViewSession session;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder:
        (context, _) => Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(session.title.isEmpty ? session.id : session.title),
                const SizedBox(height: 6),
                SelectableText('URL：${session.currentUrl}'),
                Text(
                  '历史：${session.history.length} 项；Cookie：${session.cookieCount} 个',
                ),
                Text('导航：后退 ${session.canGoBack}，前进 ${session.canGoForward}'),
                Text(
                  'JSBridge：${session.jsBridgeStatus.name}，真实请求 ${session.jsBridgeRequestCount} 次',
                ),
                Text('加载：${session.loading ? '进行中' : '完成'}'),
                Text('浮窗：${session.minimized ? '已缩小（原宿主保持）' : '页面宿主显示中'}'),
                if (session.error != null) Text('异常：${session.error}'),
              ],
            ),
          ),
        ),
  );
}

class _Checklist extends StatelessWidget {
  const _Checklist(this.platform, this.description);

  final String platform;
  final String description;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text('• $platform：$description'),
  );
}
