import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ChatDiagnosticsPage extends StatefulWidget {
  const ChatDiagnosticsPage({super.key});
  @override
  State<ChatDiagnosticsPage> createState() => _ChatDiagnosticsPageState();
}

class _ChatDiagnosticsPageState extends State<ChatDiagnosticsPage> {
  final ownerId = TextEditingController(text: '1');
  final sessionUnitId = TextEditingController();
  final title = TextEditingController(text: '聊天诊断');

  @override
  void dispose() {
    ownerId.dispose();
    sessionUnitId.dispose();
    title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('聊天窗口诊断')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const Text('使用真实 Repository、SQLite 和 HTTP 打开聊天窗口。支持移动端、平板、桌面和 Web。'),
        const SizedBox(height: 16),
        TextField(
          controller: ownerId,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Owner ID',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: sessionUnitId,
          decoration: const InputDecoration(
            labelText: 'SessionUnit ID',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: title,
          decoration: const InputDecoration(
            labelText: '标题',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () {
            final owner = int.tryParse(ownerId.text);
            final session = sessionUnitId.text.trim();
            if (owner == null || session.isEmpty) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('请输入有效参数')));
              return;
            }
            context.push(
              '/chat/${Uri.encodeComponent(session)}?ownerId=$owner&title=${Uri.encodeQueryComponent(title.text)}',
            );
          },
          child: const Text('执行：打开真实聊天窗口'),
        ),
        TextButton(
          onPressed:
              () => setState(() {
                ownerId.text = '1';
                sessionUnitId.clear();
                title.text = '聊天诊断';
              }),
          child: const Text('恢复默认'),
        ),
      ],
    ),
  );
}
