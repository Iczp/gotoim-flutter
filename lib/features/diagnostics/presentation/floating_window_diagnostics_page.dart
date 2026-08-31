import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/floating_window/floating_window.dart';

class FloatingWindowDiagnosticsPage extends ConsumerStatefulWidget {
  const FloatingWindowDiagnosticsPage({super.key});

  @override
  ConsumerState<FloatingWindowDiagnosticsPage> createState() =>
      _FloatingWindowDiagnosticsPageState();
}

class _FloatingWindowDiagnosticsPageState
    extends ConsumerState<FloatingWindowDiagnosticsPage> {
  bool _snapToEdge = true;
  String _status = '未执行';

  FloatingWindowManager get _manager => ref.read(floatingWindowManagerProvider);

  void _show(String id, Color color) {
    _manager.show(
      id: id,
      options: FloatingWindowOptions(
        snapToEdge: _snapToEdge,
        resizable: true,
        initialSize: const Size(210, 138),
      ),
      child: _DemoWindowContent(
        id: id,
        color: color,
        onClose: () => _manager.close(id),
      ),
    );
    setState(() => _status = '已显示 $id；可拖动、缩放并测试吸边。');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Floating Window 测试')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '支持平台：Android、iOS、Windows、macOS、Linux、Web。系统级 PiP/悬浮窗不属于本功能。',
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('左右自动吸边'),
            value: _snapToEdge,
            onChanged: (value) => setState(() => _snapToEdge = value),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: () => _show('custom:a', Colors.indigo),
                child: const Text('显示窗口 A'),
              ),
              FilledButton(
                onPressed: () => _show('custom:b', Colors.teal),
                child: const Text('显示窗口 B'),
              ),
              FilledButton(
                onPressed: () => _show('custom:c', Colors.deepOrange),
                child: const Text('显示窗口 C'),
              ),
              OutlinedButton(
                onPressed: _manager.closeAll,
                child: const Text('关闭全部'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('执行状态：$_status'),
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: _manager,
            builder: (context, _) {
              final windows = _manager.entries;
              return Text(
                '当前窗口：${windows.isEmpty ? '无' : windows.map((item) => item.id).join('、')}',
              );
            },
          ),
          const SizedBox(height: 16),
          const TextField(
            decoration: InputDecoration(
              labelText: '键盘避让测试',
              hintText: '打开键盘后，浮窗将被限制在键盘上方',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          const Text('验证方式：切换本应用任意页面后返回，浮窗应保持；拖动结束应吸附最近左右边缘；桌面端可拖右下角改变大小。'),
        ],
      ),
    );
  }
}

class _DemoWindowContent extends StatelessWidget {
  const _DemoWindowContent({
    required this.id,
    required this.color,
    required this.onClose,
  });
  final String id;
  final Color color;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: color,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  id,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ],
          ),
          const Spacer(),
          const Text(
            '普通 Flutter Widget',
            style: TextStyle(color: Colors.white),
          ),
          const Text('按住窗口拖动', style: TextStyle(color: Colors.white70)),
        ],
      ),
    ),
  );
}
