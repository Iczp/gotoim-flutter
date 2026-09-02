import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/target_picker/target_picker.dart';

/// 开发诊断中心 - 通用目标/人员选择器（TargetPicker）诊断页
class TargetPickerDiagnosticsPage extends StatefulWidget {
  const TargetPickerDiagnosticsPage({super.key});

  @override
  State<TargetPickerDiagnosticsPage> createState() =>
      _TargetPickerDiagnosticsPageState();
}

class _TargetPickerDiagnosticsPageState
    extends State<TargetPickerDiagnosticsPage> {
  // Configuration State
  bool _multiple = true;
  bool? _showConfirmButton;
  int _minCount = 1;
  int _maxCount = 9;
  bool _enableSearch = true;
  bool _showPreviewBar = true;
  bool _includeDisabledItems = true;
  bool _includeInitialSelected = true;
  String _title = '选择转发目标';
  String _subtitle = '逐条转发（支持多选，最多 9 项）';

  // Execution State
  String _result = '尚未调起选择器。';
  List<TargetPickerItem<Map<String, dynamic>>>? _lastSelected;
  int _elapsedMs = 0;

  // Mock Data
  static final List<TargetPickerItem<Map<String, dynamic>>> _mockCandidates = [
    const TargetPickerItem(
      id: 'target-001',
      title: '产品研发核心群',
      subtitle: '张三: 今天版本已提测，请注意验证。',
      avatarUrl: null,
      badge: '群聊',
      category: '群聊会话',
      data: {'type': 'group', 'members': 42},
    ),
    const TargetPickerItem(
      id: 'target-002',
      title: '张三 (前端主管)',
      subtitle: '[在线] 好的，收到。',
      avatarUrl: null,
      badge: '好友',
      category: '常用联系人',
      data: {'type': 'user', 'dept': '前端组'},
    ),
    const TargetPickerItem(
      id: 'target-003',
      title: '李四 (架构师)',
      subtitle: '已合并最新的 Drift 迁移逻辑。',
      avatarUrl: null,
      badge: '好友',
      category: '常用联系人',
      data: {'type': 'user', 'dept': '架构组'},
    ),
    const TargetPickerItem(
      id: 'target-004',
      title: '王五 (测试工程师)',
      subtitle: '正在回归 Android 与桌面端用例。',
      avatarUrl: null,
      badge: '好友',
      category: '常用联系人',
      disabled: true,
      disabledReason: '用户已在会话中',
      data: {'type': 'user', 'dept': 'QA'},
    ),
    const TargetPickerItem(
      id: 'target-005',
      title: 'GotoIM 官方技术支持',
      subtitle: '客服工号 #1008 为您服务',
      avatarUrl: null,
      badge: '官方客服',
      category: '服务与群组',
      data: {'type': 'customer_service'},
    ),
    const TargetPickerItem(
      id: 'target-006',
      title: '赵六 (运维工程师)',
      subtitle: '网关已恢复正常，415问题已修复。',
      avatarUrl: null,
      badge: '好友',
      category: '常用联系人',
      data: {'type': 'user', 'dept': 'SRE'},
    ),
    const TargetPickerItem(
      id: 'target-007',
      title: '移动端敏捷开发群',
      subtitle: 'Codex: 诊断中心已全部接入。',
      avatarUrl: null,
      badge: '群聊',
      category: '群聊会话',
      data: {'type': 'group', 'members': 16},
    ),
    const TargetPickerItem(
      id: 'target-008',
      title: '孙七 (UI 设计师)',
      subtitle: '请查收最新的 Sketch 交付稿。',
      avatarUrl: null,
      badge: '好友',
      category: '常用联系人',
      disabled: true,
      disabledReason: '不可选',
      data: {'type': 'user', 'dept': '设计部'},
    ),
  ];

  Future<void> _launchPicker() async {
    final watch = Stopwatch()..start();

    final disabledIds = _includeDisabledItems
        ? {'target-004', 'target-008'}
        : <String>{};
    final initialIds = _includeInitialSelected
        ? {'target-001', 'target-002'}
        : <String>{};

    final selected = await TargetPicker.show<Map<String, dynamic>>(
      context: context,
      items: _mockCandidates,
      options: TargetPickerOptions(
        title: _title,
        subtitle: _subtitle,
        multiple: _multiple,
        showConfirmButton: _showConfirmButton,
        minCount: _minCount,
        maxCount: _maxCount > 0 ? _maxCount : null,
        initialSelectedIds: initialIds,
        disabledIds: disabledIds,
        enableSearch: _enableSearch,
        showSelectedPreviewBar: _showPreviewBar,
      ),
    );

    watch.stop();

    if (!mounted) return;

    if (selected == null) {
      setState(() {
        _elapsedMs = watch.elapsedMilliseconds;
        _result = '用户取消或关闭了选择器 (耗时 ${_elapsedMs} ms)';
        _lastSelected = null;
      });
      showToast('已取消选择', position: ToastPosition.top);
      return;
    }

    final formatted = const JsonEncoder.withIndent('  ').convert(
      selected
          .map((item) => {
                'id': item.id,
                'title': item.title,
                'subtitle': item.subtitle,
                'badge': item.badge,
                'category': item.category,
                'data': item.data,
              })
          .toList(),
    );

    setState(() {
      _elapsedMs = watch.elapsedMilliseconds;
      _lastSelected = selected;
      _result = '成功选中 ${selected.length} 项 (耗时 ${_elapsedMs} ms):\n$formatted';
    });

    showSuccessToast(
      '已成功选择 ${selected.length} 个目标',
      position: ToastPosition.top,
      vibrate: true,
    );
  }

  void _applyPresetSingleDirect() {
    setState(() {
      _multiple = false;
      _showConfirmButton = false;
      _minCount = 1;
      _maxCount = 1;
      _title = '选择转发目标';
      _subtitle = '逐条转发（单选，点击立即确定）';
      _includeInitialSelected = false;
      _includeDisabledItems = true;
    });
  }

  void _applyPresetSingleWithConfirm() {
    setState(() {
      _multiple = false;
      _showConfirmButton = true;
      _minCount = 1;
      _maxCount = 1;
      _title = '选择会话';
      _subtitle = '单选模式（需点击确定按钮）';
      _includeInitialSelected = true;
      _includeDisabledItems = false;
    });
  }

  void _applyPresetMultiForward() {
    setState(() {
      _multiple = true;
      _showConfirmButton = true;
      _minCount = 1;
      _maxCount = 9;
      _title = '选择转发目标';
      _subtitle = '支持多选（最多 9 个会话）';
      _includeInitialSelected = false;
      _includeDisabledItems = false;
    });
  }

  void _applyPresetCreateGroup() {
    setState(() {
      _multiple = true;
      _showConfirmButton = true;
      _minCount = 1;
      _maxCount = 50;
      _title = '发起群聊';
      _subtitle = '请选择要拉入群聊的联系人';
      _includeInitialSelected = true;
      _includeDisabledItems = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(
        body: Center(child: Text('开发诊断仅在 Debug 模式可用。')),
      );
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('通用目标选择器诊断 (TargetPicker)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重置为默认',
            onPressed: () {
              _applyPresetMultiForward();
              setState(() => _result = '已重置配置');
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Overview Card
          _buildOverviewCard(theme, colorScheme),
          const SizedBox(height: 16),

          // 2. Presets Card
          _buildPresetsCard(theme, colorScheme),
          const SizedBox(height: 16),

          // 3. Configuration Form Card
          _buildConfigCard(theme, colorScheme),
          const SizedBox(height: 16),

          // 4. Execution & Result Card
          _buildResultCard(theme, colorScheme),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            icon: const Icon(Icons.people),
            label: const Text('调起目标选择器 (Launch TargetPicker)'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: _launchPicker,
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewCard(ThemeData theme, ColorScheme colorScheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.checklist_rtl, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text('通用选择器特性与平台矩阵', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '完全独立解耦封装，支持单选/多选、最大/最小限制、禁用项与原因提示、默认预选、搜索过滤以及已选头像预览条，可无缝复用于转发、发起群聊、分享等场景。',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusChip(platform: 'Android', supported: true, label: '半屏底部 Sheet'),
                _StatusChip(platform: 'iOS', supported: true, label: '原生触感 / 阻尼'),
                _StatusChip(platform: 'Desktop', supported: true, label: '居中约束弹层 580px'),
                _StatusChip(platform: 'Web', supported: true, label: '自适应全屏/居中'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetsCard(ThemeData theme, ColorScheme colorScheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text('快捷场景预设 (Quick Presets)', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.touch_app, size: 16),
                  label: const Text('单选直接确定 (合并转发)'),
                  onPressed: _applyPresetSingleDirect,
                ),
                ActionChip(
                  avatar: const Icon(Icons.radio_button_checked, size: 16),
                  label: const Text('单选需确定 (Radio)'),
                  onPressed: _applyPresetSingleWithConfirm,
                ),
                ActionChip(
                  avatar: const Icon(Icons.forward, size: 16),
                  label: const Text('批量转发 (最多9项)'),
                  onPressed: _applyPresetMultiForward,
                ),
                ActionChip(
                  avatar: const Icon(Icons.group_add, size: 16),
                  label: const Text('建群加人 (带禁用/预选)'),
                  onPressed: _applyPresetCreateGroup,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigCard(ThemeData theme, ColorScheme colorScheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.settings, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text('参数配置 (Parameters)', style: theme.textTheme.titleMedium),
              ],
            ),
            const Divider(height: 24),

            // Mode switch
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('多选模式 (multiple)'),
              subtitle: Text(_multiple ? '开启多选（带 Checkbox 复选框）' : '单选模式'),
              value: _multiple,
              onChanged: (val) => setState(() => _multiple = val),
            ),

            // Show confirm button
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('显示确定按钮 (showConfirmButton)'),
              subtitle: Text(
                _showConfirmButton == null
                    ? '默认 (多选显示 / 单选隐藏直接确定)'
                    : (_showConfirmButton! ? '显式开启确定按钮' : '隐藏确定按钮（点选即确定）'),
              ),
              value: _showConfirmButton ?? _multiple,
              onChanged: (val) => setState(() => _showConfirmButton = val),
            ),

            // Search Bar Switch
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用搜索栏 (enableSearch)'),
              value: _enableSearch,
              onChanged: (val) => setState(() => _enableSearch = val),
            ),

            // Selected preview bar
            if (_multiple)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('已选头像预览条 (showSelectedPreviewBar)'),
                subtitle: const Text('顶部横向展示当前已勾选头像，支持快捷点击移除'),
                value: _showPreviewBar,
                onChanged: (val) => setState(() => _showPreviewBar = val),
              ),

            // Initial selected & Disabled items
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('带默认选中项 (initialSelectedIds)'),
              subtitle: const Text('预先选中部分候选项目'),
              value: _includeInitialSelected,
              onChanged: (val) => setState(() => _includeInitialSelected = val),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('包含禁用项 (disabledIds)'),
              subtitle: const Text('部分目标置灰且显示禁用理由（如「已在群中」）'),
              value: _includeDisabledItems,
              onChanged: (val) => setState(() => _includeDisabledItems = val),
            ),

            const SizedBox(height: 8),
            // Max and Min count
            if (_multiple) ...[
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('最少选择数量 (minCount): $_minCount'),
                        Slider(
                          value: _minCount.toDouble(),
                          min: 0,
                          max: 5,
                          divisions: 5,
                          label: '$_minCount',
                          onChanged: (val) =>
                              setState(() => _minCount = val.toInt()),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('最多选择数量 (maxCount): $_maxCount'),
                        Slider(
                          value: _maxCount.toDouble(),
                          min: 1,
                          max: 20,
                          divisions: 19,
                          label: '$_maxCount',
                          onChanged: (val) =>
                              setState(() => _maxCount = val.toInt()),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(ThemeData theme, ColorScheme colorScheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.output, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text('执行状态与返回结果', style: theme.textTheme.titleMedium),
                const Spacer(),
                if (_lastSelected != null && _lastSelected!.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    tooltip: '复制结果',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _result));
                      showSuccessToast('已复制选择器结果', position: ToastPosition.top);
                    },
                  ),
              ],
            ),
            const Divider(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                _result,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.platform,
    required this.supported,
    required this.label,
  });

  final String platform;
  final bool supported;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: supported
            ? Colors.green.withValues(alpha: 0.12)
            : Colors.grey.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: supported
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.grey.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        '$platform: $label',
        style: TextStyle(
          fontSize: 11,
          color: supported ? Colors.green.shade800 : Colors.grey.shade700,
        ),
      ),
    );
  }
}
