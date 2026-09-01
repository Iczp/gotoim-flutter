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
  final TextEditingController _animateToCtrl =
      TextEditingController(text: '0.9');
  final TextEditingController _maxWidthCtrl =
      TextEditingController(text: '');
  final TextEditingController _borderRadiusCtrl =
      TextEditingController(text: '24');

  // ── 基本 ──
  bool _convertible = true;
  bool _draggable = false;
  bool _wrapContent = false;
  // ── 外观 ──
  bool _useBarrierColor = false;
  bool _useBgColor = false;
  bool _useCustomDragHandle = false;
  // ── 交互与适配 ──
  bool _dismissible = true;
  bool _enableDrag = true;
  bool _useSafeArea = false;
  bool _overlayKeyboard = false;
  // ── Header ──
  bool _showDragHandle = true;
  bool _showCloseBtn = true;
  bool _showConvertBtn = true;
  bool _useLeading = false;
  bool _useTrailing = false;
  bool _useCustomHeader = false;

  String _result = '未执行';

  @override
  void dispose() {
    _note.dispose();
    _animateToCtrl.dispose();
    _maxWidthCtrl.dispose();
    _borderRadiusCtrl.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final watch = Stopwatch()..start();
    final maxW = double.tryParse(_maxWidthCtrl.text.trim());
    final borderR = double.tryParse(_borderRadiusCtrl.text.trim()) ?? 24;

    await AdaptivePage.open<void>(
      context,
      config: AdaptivePageConfig(
        title: 'AdaptivePage 诊断',
        canConvertToPage: _convertible,
        sheetSizingMode: _draggable
            ? AdaptiveSheetSizingMode.draggable
            : AdaptiveSheetSizingMode.content,
        maxContentHeightFactor: _wrapContent ? null : .75,
        // 外观
        backgroundColor: _useBgColor
            ? Colors.deepPurple.shade900.withValues(alpha: .95)
            : null,
        barrierColor:
            _useBarrierColor ? Colors.blue.withValues(alpha: .4) : null,
        sheetBorderRadius: borderR,
        maxWidth: maxW,
        // 交互与适配
        isDismissible: _dismissible,
        enableDrag: _enableDrag,
        useSafeArea: _useSafeArea,
        keyboardBehavior: _overlayKeyboard
            ? AdaptiveKeyboardBehavior.overlay
            : AdaptiveKeyboardBehavior.resize,
        // Header
        showDragHandle: _showDragHandle,
        dragHandleColor: _useCustomDragHandle ? Colors.teal : null,
        dragHandleSize:
            _useCustomDragHandle ? const Size(48, 6) : null,
        showCloseButton: _showCloseBtn,
        showConvertButton: _showConvertBtn,
        leadingAction: _useLeading
            ? const Icon(Icons.star, color: Colors.amber)
            : null,
        trailingActions: _useTrailing
            ? [
                IconButton(
                  tooltip: '自定义按钮',
                  icon: const Icon(Icons.info_outline),
                  onPressed: () {},
                ),
              ]
            : [],
        headerBuilder: _useCustomHeader ? _customHeader : null,
      ),
      builder: (_, controller) => _AdaptiveDemo(
        note: _note,
        controller: controller,
        draggable: _draggable,
        animateTo: _animateToCtrl,
      ),
    );
    if (!mounted) return;
    setState(() => _result =
        '完成，耗时 ${watch.elapsedMilliseconds} ms；备注：${_note.text.isEmpty ? '（空）' : _note.text}');
  }

  Widget _customHeader(BuildContext context, dynamic ctrl) {
    final controller = ctrl as AdaptivePageController;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      color: Colors.orange.withValues(alpha: .15),
      child: Row(
        children: [
          const Icon(Icons.build, size: 18, color: Colors.orange),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '🛠 自定义 Header',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: controller.close,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(
          body: Center(child: Text('开发诊断仅在 Debug 模式可用。')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('AdaptivePage 诊断')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('验证半屏/全页转换、新增参数（外观、交互、Header）及返回值。'),
          const SizedBox(height: 12),

          // ── 基本 ──
          _Section(
            title: '基本',
            children: [
              SwitchListTile(
                value: _convertible,
                onChanged: (v) => setState(() => _convertible = v),
                title: const Text('允许转为完整页面'),
                dense: true,
              ),
              SwitchListTile(
                value: _draggable,
                onChanged: (v) => setState(() {
                  _draggable = v;
                  if (v) _wrapContent = false;
                }),
                title: const Text('Draggable 高度拖拽模式'),
                dense: true,
              ),
              SwitchListTile(
                value: _wrapContent,
                onChanged: (v) => setState(() {
                  _wrapContent = v;
                  if (v) _draggable = false;
                }),
                title: const Text('内容自适应高度 Wrap Content (heightFactor: null)'),
                dense: true,
              ),
            ],
          ),

          // ── 外观 ──
          _Section(
            title: '外观',
            children: [
              SwitchListTile(
                value: _useBgColor,
                onChanged: (v) => setState(() => _useBgColor = v),
                title: const Text('深紫背景色'),
                dense: true,
              ),
              SwitchListTile(
                value: _useBarrierColor,
                onChanged: (v) => setState(() => _useBarrierColor = v),
                title: const Text('蓝色遮罩 barrierColor'),
                dense: true,
              ),
              SwitchListTile(
                value: _useCustomDragHandle,
                onChanged: (v) => setState(() => _useCustomDragHandle = v),
                title: const Text('自定义拖拽条样式 (青色粗条 48x6)'),
                dense: true,
              ),
              _LabeledInput(
                label: '顶部圆角 sheetBorderRadius',
                controller: _borderRadiusCtrl,
                hint: '默认 24',
              ),
              _LabeledInput(
                label: 'maxWidth（留空=不限）',
                controller: _maxWidthCtrl,
                hint: '如 560',
              ),
            ],
          ),

          // ── 交互与适配 ──
          _Section(
            title: '交互与适配',
            children: [
              SwitchListTile(
                value: _dismissible,
                onChanged: (v) => setState(() => _dismissible = v),
                title: const Text('点击遮罩可关闭 isDismissible'),
                dense: true,
              ),
              SwitchListTile(
                value: _enableDrag,
                onChanged: (v) => setState(() => _enableDrag = v),
                title: const Text('拖拽关闭 enableDrag'),
                dense: true,
              ),
              SwitchListTile(
                value: _useSafeArea,
                onChanged: (v) => setState(() => _useSafeArea = v),
                title: const Text('启用 useSafeArea (避开系统栏/刘海)'),
                dense: true,
              ),
              SwitchListTile(
                value: _overlayKeyboard,
                onChanged: (v) => setState(() => _overlayKeyboard = v),
                title: const Text('键盘策略: overlay (不避让/不抬升)'),
                dense: true,
              ),
            ],
          ),

          // ── Header ──
          _Section(
            title: 'Header',
            children: [
              SwitchListTile(
                value: _showDragHandle,
                onChanged: (v) => setState(() => _showDragHandle = v),
                title: const Text('显示拖拽条 showDragHandle'),
                dense: true,
              ),
              SwitchListTile(
                value: _showCloseBtn,
                onChanged: (v) => setState(() => _showCloseBtn = v),
                title: const Text('显示关闭按钮 showCloseButton'),
                dense: true,
              ),
              SwitchListTile(
                value: _showConvertBtn,
                onChanged: (v) => setState(() => _showConvertBtn = v),
                title: const Text('显示转换按钮 showConvertButton'),
                dense: true,
              ),
              SwitchListTile(
                value: _useLeading,
                onChanged: (v) => setState(() => _useLeading = v),
                title: const Text('自定义 leadingAction（星形图标）'),
                dense: true,
              ),
              SwitchListTile(
                value: _useTrailing,
                onChanged: (v) => setState(() => _useTrailing = v),
                title: const Text('trailingActions（info 按钮）'),
                dense: true,
              ),
              SwitchListTile(
                value: _useCustomHeader,
                onChanged: (v) => setState(() => _useCustomHeader = v),
                title: const Text('完全自定义 headerBuilder（覆盖上述所有）'),
                dense: true,
              ),
            ],
          ),

          const SizedBox(height: 8),
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

// ── Demo 内容页 ───────────────────────────────────────────────────────────────

class _AdaptiveDemo extends StatelessWidget {
  const _AdaptiveDemo({
    required this.note,
    required this.controller,
    required this.draggable,
    required this.animateTo,
  });
  final TextEditingController note;
  final AdaptivePageController controller;
  final bool draggable;
  final TextEditingController animateTo;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: controller.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Text(controller.isSheet
            ? 'Sheet 模式（isSheet = true）'
            : 'Page 模式（isPage = true）'),
        const SizedBox(height: 4),
        Text(
          'currentSize: ${controller.currentSize.toStringAsFixed(3)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: note,
          decoration: const InputDecoration(
            labelText: '备注（转完整页后应保留）',
            border: OutlineInputBorder(),
          ),
        ),
        if (controller.isPage) ...[
          const SizedBox(height: 16),
          const Text('完整页面附加内容：账号、地区、权限、更多资料。'),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: controller.expandSheet,
                child: const Text('展开'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: controller.collapseSheet,
                child: const Text('收起'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // animateTo
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: animateTo,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'animateTo 目标比例 (0~1)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 80,
              child: FilledButton(
                onPressed: () {
                  final v = double.tryParse(animateTo.text.trim());
                  if (v != null) controller.animateTo(v);
                },
                child: const Text('执行'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // onResult
        FilledButton.tonal(
          onPressed: () => controller.onResult('用户点击了返回值按钮'),
          child: const Text('onResult 携带返回值关闭'),
        ),
        if (draggable) ...[
          const SizedBox(height: 16),
          for (var i = 0; i < 30; i++)
            ListTile(title: Text('长列表示例 ${i + 1}')),
        ],
      ],
    );
  }
}

// ── 辅助组件 ──────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(
            title,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: Theme.of(context).colorScheme.primary),
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Column(children: children),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _LabeledInput extends StatelessWidget {
  const _LabeledInput({
    required this.label,
    required this.controller,
    this.hint,
  });
  final String label;
  final TextEditingController controller;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
