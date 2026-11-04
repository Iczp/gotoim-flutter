import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:multiview_desktop/multiview_desktop.dart';

/// 全局共享状态：证明单 Engine + 单 Dart Isolate 跨窗口零 IPC 实时共享
class SharedChatState extends ChangeNotifier {
  static final SharedChatState instance = SharedChatState._();
  SharedChatState._();

  final String isolateId = Isolate.current.debugName ?? 'main_isolate';
  final int isolateHashCode = identityHashCode(Isolate.current);

  final List<Map<String, dynamic>> _messages = [
    {
      'id': 'm_0',
      'sender': 'System',
      'text': 'MultiView 单引擎原型已就绪，所有窗口共享当前 Dart Isolate 状态',
      'time': DateTime.now(),
    }
  ];

  List<Map<String, dynamic>> get messages => List.unmodifiable(_messages);

  void sendMessage(String sender, String text) {
    if (text.trim().isEmpty) return;
    _messages.add({
      'id': 'm_${DateTime.now().millisecondsSinceEpoch}',
      'sender': sender,
      'text': text.trim(),
      'time': DateTime.now(),
    });
    notifyListeners();
  }

  void clear() {
    _messages.clear();
    notifyListeners();
  }
}

List<String> gArgs = [];

void main(List<String> args) {
  gArgs = args;
  WidgetsFlutterBinding.ensureInitialized();

  runMultiApp(
    home: (globalScopeContext, id) => MainWindowRoot(viewId: id),
    globalScope: (child) => child,
    config: MultiAppConfig(
      generalParams: MultiPlatformParams(
        closeMode: CloseMode.softCascade,
        closeAppAfterLastWindowClosed: true,
      ),
    ),
  );
}

class MainWindowRoot extends StatelessWidget {
  const MainWindowRoot({required this.viewId, super.key});
  final int viewId;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'GotoIM Single-Engine MultiView PoC (Main)',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: MainWindowPage(viewId: viewId),
    );
  }
}

class MainWindowPage extends StatefulWidget {
  const MainWindowPage({required this.viewId, super.key});
  final int viewId;

  @override
  State<MainWindowPage> createState() => _MainWindowPageState();
}

class _MainWindowPageState extends State<MainWindowPage> {
  final Set<String> _openChatSessions = {};

  @override
  void initState() {
    super.initState();
    if (gArgs.contains('--auto-open-4')) {
      Future.delayed(const Duration(seconds: 2), () {
        for (int i = 1; i <= 4; i++) {
          _openChat('session_$i', '测试好友 $i');
        }
      });
    }
    if (gArgs.contains('--auto-open-9')) {
      Future.delayed(const Duration(seconds: 2), () {
        for (int i = 1; i <= 9; i++) {
          _openChat('session_$i', '测试好友 $i');
        }
      });
    }
  }

  void _openChat(String sessionId, String title) {
    _openChatSessions.add(sessionId);
    openWindow(
      (ctx, childViewId) => ChatSubWindowRoot(
        viewId: childViewId,
        sessionId: sessionId,
        title: title,
        onClosed: () {
          if (mounted) {
            setState(() => _openChatSessions.remove(sessionId));
          }
        },
      ),
      options: WindowOptions(
        title: '聊天: $title (View $sessionId)',
        size: const Size(720, 520),
      ),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = SharedChatState.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('GotoIM MultiView POC - 主窗口 (单 Engine)'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            tooltip: '清空消息',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => state.clear(),
          ),
        ],
      ),
      body: Row(
        children: [
          // 左侧：会话列表与独立窗口触发区
          SizedBox(
            width: 320,
            child: Card(
              margin: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '多窗口拓扑验证',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text('Main ViewId: ${widget.viewId}'),
                        Text('Isolate: ${state.isolateId} (#${state.isolateHashCode})'),
                        Text('活动会话窗口数: ${_openChatSessions.length}'),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      itemCount: 9,
                      itemBuilder: (context, idx) {
                        final id = 'session_${idx + 1}';
                        final title = '测试好友 ${idx + 1}';
                        final isOpen = _openChatSessions.contains(id);
                        return ListTile(
                          leading: CircleAvatar(child: Text('${idx + 1}')),
                          title: Text(title),
                          subtitle: Text(isOpen ? '窗口已打开' : '未打开'),
                          trailing: ElevatedButton(
                            onPressed: () => _openChat(id, title),
                            child: Text(isOpen ? '聚焦' : '打开'),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 右侧：全局实时共享消息流
          Expanded(
            child: Card(
              margin: const EdgeInsets.fromLTRB(0, 8, 8, 8),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    alignment: Alignment.centerLeft,
                    child: const Text(
                      '全局单 Dart Isolate 实时消息总线 (任何窗口输入立即可见):',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: AnimatedBuilder(
                      animation: state,
                      builder: (context, _) {
                        return ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: state.messages.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 6),
                          itemBuilder: (context, i) {
                            final msg = state.messages[i];
                            return Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '[${msg['sender']}] ${msg['text']}',
                                style: const TextStyle(fontSize: 13),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ChatSubWindowRoot extends StatelessWidget {
  const ChatSubWindowRoot({
    required this.viewId,
    required this.sessionId,
    required this.title,
    this.onClosed,
    super.key,
  });

  final int viewId;
  final String sessionId;
  final String title;
  final VoidCallback? onClosed;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '聊天 - $title',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: ChatSubWindowView(
        viewId: viewId,
        sessionId: sessionId,
        title: title,
        onClosed: onClosed,
      ),
    );
  }
}

class ChatSubWindowView extends StatefulWidget {
  const ChatSubWindowView({
    required this.viewId,
    required this.sessionId,
    required this.title,
    this.onClosed,
    super.key,
  });

  final int viewId;
  final String sessionId;
  final String title;
  final VoidCallback? onClosed;

  @override
  State<ChatSubWindowView> createState() => _ChatSubWindowViewState();
}

class _ChatSubWindowViewState extends State<ChatSubWindowView> {
  final TextEditingController _input = TextEditingController();

  @override
  void dispose() {
    widget.onClosed?.call();
    _input.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    SharedChatState.instance.sendMessage(widget.title, text);
  }

  @override
  Widget build(BuildContext context) {
    final state = SharedChatState.instance;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.title} (ViewId: ${widget.viewId})'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.amber.shade50,
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 18, color: Colors.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '单 Engine 验证：Isolate #${state.isolateHashCode} | 共享内存消息: ${state.messages.length}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: AnimatedBuilder(
              animation: state,
              builder: (context, _) {
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: state.messages.length,
                  itemBuilder: (context, i) {
                    final msg = state.messages[i];
                    final isMe = msg['sender'] == widget.title;
                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.indigo.shade100 : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('${msg['sender']}: ${msg['text']}'),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    decoration: const InputDecoration(
                      hintText: '输入消息 (测试中文 IME、复制粘贴)...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _send,
                  child: const Text('发送'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
