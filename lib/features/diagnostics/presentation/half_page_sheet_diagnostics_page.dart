import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/half_page_sheet.dart';

/// 可实际打开半屏页、调整核心参数并记录返回结果的开发诊断入口。
///
/// 不访问网络或本地数据库，支持 Android、iOS、Windows、macOS、Linux 与 Web。
class HalfPageSheetDiagnosticsPage extends StatefulWidget {
  const HalfPageSheetDiagnosticsPage({super.key});

  @override
  State<HalfPageSheetDiagnosticsPage> createState() =>
      _HalfPageSheetDiagnosticsPageState();
}

class _HalfPageSheetDiagnosticsPageState
    extends State<HalfPageSheetDiagnosticsPage> {
  double _heightFactor = .62;
  bool _showHandle = true;
  bool _customHandle = false;
  bool _safeArea = true;
  bool _dismissible = true;
  bool _enableDrag = true;
  bool _resizeForKeyboard = true;
  String _status = '未执行';
  String _result = '尚未打开半屏页。';

  Future<void> _open() async {
    final stopwatch = Stopwatch()..start();
    setState(() => _status = '执行中');
    final result = await showHalfPageSheet<String>(
      context: context,
      options: HalfPageSheetOptions(
        heightFactor: _heightFactor,
        useSafeArea: _safeArea,
        isDismissible: _dismissible,
        enableDrag: _enableDrag,
        showDragHandle: _showHandle,
        dragHandleColor: _customHandle ? Colors.teal : null,
        dragHandleSize: _customHandle ? const Size(48, 5) : null,
        keyboardBehavior:
            _resizeForKeyboard
                ? HalfPageSheetKeyboardBehavior.resize
                : HalfPageSheetKeyboardBehavior.overlay,
        routeSettings: const RouteSettings(
          name: '/diagnostics/half-page-sheet',
        ),
      ),
      builder:
          (sheetContext) => _DiagnosticSheet(
            onComplete: () => Navigator.pop(sheetContext, 'complete'),
          ),
    );
    stopwatch.stop();
    if (!mounted) return;
    setState(() {
      _status = '成功';
      _result =
          '返回值：${result ?? 'null（点击遮罩、返回键或下滑关闭）'}\n'
          '耗时：${stopwatch.elapsedMilliseconds} ms\n'
          '输入：heightFactor=${_heightFactor.toStringAsFixed(2)}, '
          'safeArea=$_safeArea, dismissible=$_dismissible, drag=$_enableDrag, '
          'keyboard=${_resizeForKeyboard ? 'resize' : 'overlay'}';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(body: Center(child: Text('开发诊断仅在 Debug 模式可用。')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('半屏页组件诊断')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text(
            '实际打开共享 showHalfPageSheet。可验证固定高度、键盘避让、关闭方式与自定义拖拽条；不产生网络或数据库写入。',
            style: TextStyle(height: 1.45),
          ),
          const SizedBox(height: 16),
          Text('高度比例：${_heightFactor.toStringAsFixed(2)}'),
          Slider(
            value: _heightFactor,
            min: .35,
            max: .95,
            divisions: 12,
            label: _heightFactor.toStringAsFixed(2),
            onChanged: (value) => setState(() => _heightFactor = value),
          ),
          SwitchListTile(
            value: _showHandle,
            onChanged: (value) => setState(() => _showHandle = value),
            title: const Text('显示拖拽指示条'),
          ),
          SwitchListTile(
            value: _customHandle,
            onChanged:
                _showHandle
                    ? (value) => setState(() => _customHandle = value)
                    : null,
            title: const Text('自定义拖拽条颜色与尺寸'),
            subtitle: const Text('青绿色，48 × 5'),
          ),
          SwitchListTile(
            value: _safeArea,
            onChanged: (value) => setState(() => _safeArea = value),
            title: const Text('避开系统安全区'),
          ),
          SwitchListTile(
            value: _dismissible,
            onChanged: (value) => setState(() => _dismissible = value),
            title: const Text('点击遮罩关闭'),
          ),
          SwitchListTile(
            value: _enableDrag,
            onChanged: (value) => setState(() => _enableDrag = value),
            title: const Text('下拉关闭'),
          ),
          SwitchListTile(
            value: _resizeForKeyboard,
            onChanged: (value) => setState(() => _resizeForKeyboard = value),
            title: const Text('键盘出现时上移'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _status == '执行中' ? null : _open,
            icon: const Icon(Icons.vertical_align_top),
            label: const Text('实际打开半屏页'),
          ),
          const SizedBox(height: 20),
          Text('执行状态：$_status', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          SelectableText(_result),
          const SizedBox(height: 16),
          const Text(
            '平台支持：Android ✓  iOS/iPad ✓  Windows ✓  macOS ✓  Linux ✓  Web ✓',
          ),
        ],
      ),
    );
  }
}

class _DiagnosticSheet extends StatelessWidget {
  const _DiagnosticSheet({required this.onComplete});
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: Column(
      children: <Widget>[
        const ListTile(
          title: Text('半屏页实际预览'),
          subtitle: Text('点击输入框验证键盘避让；可使用返回、遮罩或下拉关闭。'),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            decoration: InputDecoration(
              labelText: '键盘验证输入',
              hintText: '输入任意内容',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Expanded(child: Center(child: Text('可滚动/可分页内容区域预留'))),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onComplete,
              child: const Text('完成并返回 complete'),
            ),
          ),
        ),
      ],
    ),
  );
}
