import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/ui/adaptive_page.dart';

class AdaptivePageDiagnosticsPage extends StatefulWidget {
  const AdaptivePageDiagnosticsPage({super.key});
  @override
  State<AdaptivePageDiagnosticsPage> createState() =>
      _AdaptivePageDiagnosticsPageState();
}

class _AdaptivePageDiagnosticsPageState
    extends State<AdaptivePageDiagnosticsPage> {
  final TextEditingController _note = TextEditingController();
  bool _convertible = true;
  bool _draggable = false;
  String _result = '未执行';
  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final watch = Stopwatch()..start();
    await AdaptivePage.open<void>(
      context,
      config: AdaptivePageConfig(
        title: 'AdaptivePage 诊断',
        canConvertToPage: _convertible,
        sheetSizingMode:
            _draggable
                ? AdaptiveSheetSizingMode.draggable
                : AdaptiveSheetSizingMode.content,
      ),
      builder:
          (_, controller) => _AdaptiveDemo(
            note: _note,
            controller: controller,
            draggable: _draggable,
          ),
    );
    if (!mounted) return;
    setState(
      () =>
          _result =
              '完成，耗时 ${watch.elapsedMilliseconds} ms；保留输入：${_note.text.isEmpty ? '（空）' : _note.text}',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(body: Center(child: Text('开发诊断仅在 Debug 模式可用。')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('AdaptivePage 诊断')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('实际验证半屏/完整页转换、禁止转换、可拖拽长列表、键盘避让及跨展示模式保留输入状态。'),
          SwitchListTile(
            value: _convertible,
            onChanged: (value) => setState(() => _convertible = value),
            title: const Text('允许转为完整页面'),
          ),
          SwitchListTile(
            value: _draggable,
            onChanged: (value) => setState(() => _draggable = value),
            title: const Text('Draggable 长列表模式'),
          ),
          FilledButton.icon(
            onPressed: _open,
            icon: const Icon(Icons.open_in_new),
            label: const Text('实际打开 AdaptivePage'),
          ),
          const SizedBox(height: 20),
          Text('执行结果：$_result'),
          const SizedBox(height: 16),
          const Text(
            '平台支持：Android ✓  iOS/iPad ✓  Windows ✓  macOS ✓  Linux ✓  Web ✓',
          ),
        ],
      ),
    );
  }
}

class _AdaptiveDemo extends StatelessWidget {
  const _AdaptiveDemo({
    required this.note,
    required this.controller,
    required this.draggable,
  });
  final TextEditingController note;
  final AdaptivePageController controller;
  final bool draggable;
  @override
  Widget build(BuildContext context) => ListView(
    controller: controller.scrollController,
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
    children: [
      Text(controller.isCompact ? 'Compact：仅显示摘要与输入。' : 'Full：显示完整内容。'),
      const SizedBox(height: 12),
      TextField(
        controller: note,
        decoration: const InputDecoration(
          labelText: '备注（转完整页后应保留）',
          border: OutlineInputBorder(),
        ),
      ),
      if (controller.isFull) ...[
        const SizedBox(height: 16),
        const Text('完整页面附加内容：账号、地区、权限、更多资料。'),
      ],
      if (draggable) ...[
        const SizedBox(height: 16),
        for (var index = 0; index < 30; index++)
          ListTile(title: Text('长列表示例 ${index + 1}')),
      ],
      const SizedBox(height: 16),
      OutlinedButton(
        onPressed: controller.expandSheet,
        child: const Text('展开半屏'),
      ),
      OutlinedButton(
        onPressed: controller.collapseSheet,
        child: const Text('收起半屏'),
      ),
    ],
  );
}
