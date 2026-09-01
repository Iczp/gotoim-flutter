import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/app_toast.dart';

class ToastDiagnosticsPage extends StatefulWidget {
  const ToastDiagnosticsPage({super.key});

  @override
  State<ToastDiagnosticsPage> createState() => _ToastDiagnosticsPageState();
}

class _ToastDiagnosticsPageState extends State<ToastDiagnosticsPage> {
  final TextEditingController _messageCtrl = TextEditingController(
    text: '这是一条操作提示消息，支持多行文本自动换行排版与透明度展示。',
  );
  final TextEditingController _actionLabelCtrl =
      TextEditingController(text: '撤销');

  ToastType _selectedType = ToastType.success;
  ToastPosition? _selectedPosition;
  double _opacity = 0.95;
  double _offsetX = 0.0;
  double _offsetY = 0.0;
  bool? _vibrate;
  bool? _playSound;
  bool _includeAction = false;
  int? _maxLines;
  String _result = '未触发';

  static const _sampleTexts = [
    ('单行短句', '操作成功！'),
    ('中等提示', '新消息已同步完成，本地数据库已更新。'),
    (
      '长段落多行',
      '同步失败：服务器返回 502 Bad Gateway，请检查网关配置以及 SignalR 长连接状态，确认无误后点击重试。'
    ),
    (
      '超长多行详细信息',
      '【详细诊断日志】\n'
          '• 请求链路: /api/chat/messages/sync\n'
          '• 设备 ID: dev-client-windows-001\n'
          '• 耗时: 128ms\n'
          '• 状态码: 200 OK，已写入本地 SQLite DAO。'
    ),
  ];

  @override
  void dispose() {
    _messageCtrl.dispose();
    _actionLabelCtrl.dispose();
    super.dispose();
  }

  void _triggerToast() {
    final watch = Stopwatch()..start();
    final message = _messageCtrl.text.trim();
    if (message.isEmpty) return;

    final offset = (_offsetX != 0.0 || _offsetY != 0.0)
        ? Offset(_offsetX, _offsetY)
        : null;

    final success = showToast(
      message,
      options: ToastOptions(
        type: _selectedType,
        position: _selectedPosition,
        offset: offset,
        opacity: _opacity,
        maxLines: _maxLines,
        vibrate: _vibrate,
        playSound: _playSound,
        actionLabel: _includeAction ? _actionLabelCtrl.text.trim() : null,
        onAction: _includeAction
            ? () {
                setState(() => _result = '用户点击了 Toast 操作按钮！');
              }
            : null,
      ),
    );

    setState(() {
      _result = success
          ? '成功弹出 Toast，耗时 ${watch.elapsedMilliseconds} ms\n'
              '位置: ${_selectedPosition?.name ?? "跟随全局(${AppToastConfig.defaultPosition.name})"}\n'
              '偏移: Offset(${_offsetX.toStringAsFixed(0)}, ${_offsetY.toStringAsFixed(0)})\n'
              '透明度: ${(_opacity * 100).toStringAsFixed(0)}%\n'
              '振动: ${_vibrate ?? "全局(${AppToastConfig.defaultVibrate})"} | 声音: ${_playSound ?? "全局(${AppToastConfig.defaultPlaySound})"}'
          : '弹出失败（ScaffoldMessenger 未就绪）';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(
        body: Center(child: Text('开发诊断仅在 Debug 模式可用。')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Toast 提示与反馈诊断')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('验证全局 Toast 悬浮位置、自定义像素偏移量、透明度、多行排版、触觉振动与发声。'),
          const SizedBox(height: 12),

          // ── 全局配置 ──
          _Section(
            title: '全局默认配置 (AppToastConfig)',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Text('全局默认位置：'),
                    const SizedBox(width: 8),
                    DropdownButton<ToastPosition>(
                      value: AppToastConfig.defaultPosition,
                      items: ToastPosition.values
                          .map(
                            (p) => DropdownMenuItem(
                              value: p,
                              child: Text(switch (p) {
                                ToastPosition.top => '顶部 (Top)',
                                ToastPosition.center => '居中 (Center)',
                                ToastPosition.bottom => '底部 (Bottom)',
                              }),
                            ),
                          )
                          .toList(),
                      onChanged: (pos) {
                        if (pos != null) {
                          setState(() => AppToastConfig.defaultPosition = pos);
                        }
                      },
                    ),
                  ],
                ),
              ),
              SwitchListTile(
                value: AppToastConfig.defaultVibrate,
                onChanged: (v) => setState(() => AppToastConfig.defaultVibrate = v),
                title: const Text('全局默认启用振动'),
                dense: true,
              ),
              SwitchListTile(
                value: AppToastConfig.defaultPlaySound,
                onChanged: (v) => setState(() => AppToastConfig.defaultPlaySound = v),
                title: const Text('全局默认启用声音'),
                dense: true,
              ),
            ],
          ),

          // ── 文本内容与多行示例 ──
          _Section(
            title: '文本内容与多行示例',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: TextField(
                  controller: _messageCtrl,
                  maxLines: 4,
                  minLines: 2,
                  decoration: const InputDecoration(
                    labelText: '提示文本（可输入多行）',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _sampleTexts.map((sample) {
                    return ActionChip(
                      label: Text(sample.$1),
                      onPressed: () {
                        setState(() => _messageCtrl.text = sample.$2);
                      },
                    );
                  }).toList(),
                ),
              ),
            ],
          ),

          // ── 位置、偏移与透明度 ──
          _Section(
            title: '位置、偏移与透明度',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    const Text('位置呈现：'),
                    const SizedBox(width: 8),
                    DropdownButton<ToastPosition?>(
                      value: _selectedPosition,
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('跟随全局配置'),
                        ),
                        ...ToastPosition.values.map(
                          (p) => DropdownMenuItem(
                            value: p,
                            child: Text(switch (p) {
                              ToastPosition.top => '顶部 (Top)',
                              ToastPosition.center => '居中 (Center)',
                              ToastPosition.bottom => '底部 (Bottom)',
                            }),
                          ),
                        ),
                      ],
                      onChanged: (pos) => setState(() => _selectedPosition = pos),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    Text('背景透明度: ${(_opacity * 100).toStringAsFixed(0)}%'),
                    Expanded(
                      child: Slider(
                        value: _opacity,
                        min: 0.2,
                        max: 1.0,
                        divisions: 16,
                        label: '${(_opacity * 100).toStringAsFixed(0)}%',
                        onChanged: (v) => setState(() => _opacity = v),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Row(
                  children: [
                    Text('水平偏移 X: ${_offsetX.toStringAsFixed(0)} px'),
                    Expanded(
                      child: Slider(
                        value: _offsetX,
                        min: -100.0,
                        max: 100.0,
                        divisions: 40,
                        label: '${_offsetX.toStringAsFixed(0)} px',
                        onChanged: (v) => setState(() => _offsetX = v),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Text('垂直偏移 Y: ${_offsetY.toStringAsFixed(0)} px'),
                    Expanded(
                      child: Slider(
                        value: _offsetY,
                        min: -150.0,
                        max: 150.0,
                        divisions: 60,
                        label: '${_offsetY.toStringAsFixed(0)} px',
                        onChanged: (v) => setState(() => _offsetY = v),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── 反馈与动作 ──
          _Section(
            title: '语义、反馈与操作按钮',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    const Text('语义类型：'),
                    const SizedBox(width: 8),
                    DropdownButton<ToastType>(
                      value: _selectedType,
                      items: ToastType.values
                          .map(
                            (t) => DropdownMenuItem(
                              value: t,
                              child: Text(switch (t) {
                                ToastType.success => '✅ 成功 (success)',
                                ToastType.error => '❌ 错误 (error)',
                                ToastType.warning => '⚠️ 警告 (warning)',
                                ToastType.info => 'ℹ️ 信息 (info)',
                              }),
                            ),
                          )
                          .toList(),
                      onChanged: (t) {
                        if (t != null) setState(() => _selectedType = t);
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    const Text('振动控制：'),
                    const SizedBox(width: 8),
                    DropdownButton<bool?>(
                      value: _vibrate,
                      items: const [
                        DropdownMenuItem(value: null, child: Text('跟随全局')),
                        DropdownMenuItem(value: true, child: Text('强制振动')),
                        DropdownMenuItem(value: false, child: Text('强制不振动')),
                      ],
                      onChanged: (v) => setState(() => _vibrate = v),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    const Text('声音控制：'),
                    const SizedBox(width: 8),
                    DropdownButton<bool?>(
                      value: _playSound,
                      items: const [
                        DropdownMenuItem(value: null, child: Text('跟随全局')),
                        DropdownMenuItem(value: true, child: Text('强制发声')),
                        DropdownMenuItem(value: false, child: Text('强制不发声')),
                      ],
                      onChanged: (v) => setState(() => _playSound = v),
                    ),
                  ],
                ),
              ),
              SwitchListTile(
                value: _includeAction,
                onChanged: (v) => setState(() => _includeAction = v),
                title: const Text('包含操作按钮'),
                dense: true,
              ),
              if (_includeAction)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: _actionLabelCtrl,
                    decoration: const InputDecoration(
                      labelText: '按钮文字',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _triggerToast,
            icon: const Icon(Icons.notifications_active_outlined),
            label: const Text('弹出当前配置 Toast'),
          ),

          const SizedBox(height: 12),
          // 快捷方法按钮组
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => showSuccessToast('操作成功！'),
                child: const Text('快捷 Success'),
              ),
              OutlinedButton(
                onPressed: () => showErrorToast(
                  '网络连接超时：\n'
                  '无法连接到网关服务 (504 Gateway Timeout)，请检查移动数据或 Wi-Fi。',
                  options: const ToastOptions(opacity: 0.92),
                ),
                child: const Text('快捷多行 Error'),
              ),
              OutlinedButton(
                onPressed: () => showWarningToast(
                  '账号安全提示：已在其他 Windows 客户端登录',
                  options: const ToastOptions(
                    position: ToastPosition.top,
                    opacity: 0.90,
                  ),
                ),
                child: const Text('快捷顶部 Warning'),
              ),
              OutlinedButton(
                onPressed: () => showInfoToast(
                  '正在同步离线联系人与聊天历史...',
                  options: const ToastOptions(
                    position: ToastPosition.center,
                    opacity: 0.88,
                  ),
                ),
                child: const Text('快捷居中 Info'),
              ),
            ],
          ),

          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('执行结果：\n$_result'),
          ),
          const SizedBox(height: 16),
          const Text(
            '平台支持：Android ✓  iOS/iPad ✓  Windows ✓  macOS ✓  Linux ✓  Web ✓',
          ),
        ],
      ),
    );
  }
}

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
