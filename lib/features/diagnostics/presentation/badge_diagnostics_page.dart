import 'package:flutter/material.dart';
import '../../../../core/widgets/app_badge.dart';

/// AppBadge 动效角标开发诊断中心页面
class BadgeDiagnosticsPage extends StatefulWidget {
  const BadgeDiagnosticsPage({super.key});

  @override
  State<BadgeDiagnosticsPage> createState() => _BadgeDiagnosticsPageState();
}

class _BadgeDiagnosticsPageState extends State<BadgeDiagnosticsPage> {
  int _count = 19;
  bool _dot = false;
  bool _showZero = false;
  int _maxCount = 99;
  AppBadgeSize _size = AppBadgeSize.normal;
  Color _color = const Color(0xFFFF4D4F);

  final List<String> _log = [];

  void _recordLog(String action) {
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';
    setState(() {
      _log.insert(0, '[$timeStr] $action (当前 count: $_count, dot: $_dot)');
      if (_log.length > 30) _log.removeLast();
    });
  }

  void _setCount(int newCount, String reason) {
    final old = _count;
    setState(() {
      _count = newCount;
    });
    _recordLog('$reason: $old → $newCount');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AppBadge 动效角标诊断'),
        actions: [
          IconButton(
            tooltip: '重置为默认值(19)',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              setState(() {
                _count = 19;
                _dot = false;
                _showZero = false;
                _maxCount = 99;
                _size = AppBadgeSize.normal;
                _color = const Color(0xFFFF4D4F);
              });
              _recordLog('已重置默认状态');
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 1. 动效预览区域 ──────────────────────────────────────────────
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Column(
                children: [
                  Text(
                    '当前实时效果',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 形态 A：独立行内 Badge
                      Column(
                        children: [
                          Container(
                            height: 60,
                            alignment: Alignment.center,
                            child: AppBadge(
                              count: _count,
                              dot: _dot,
                              maxCount: _maxCount,
                              showZero: _showZero,
                              size: _size,
                              color: _color,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text('行内独立形态', style: theme.textTheme.bodySmall),
                        ],
                      ),

                      // 形态 B：包裹圆形头像右上角
                      Column(
                        children: [
                          SizedBox(
                            height: 60,
                            child: Center(
                              child: AppBadge(
                                count: _count,
                                dot: _dot,
                                maxCount: _maxCount,
                                showZero: _showZero,
                                size: _size,
                                color: _color,
                                child: CircleAvatar(
                                  radius: 24,
                                  backgroundColor: colorScheme.primaryContainer,
                                  child: Icon(
                                    Icons.person_rounded,
                                    color: colorScheme.onPrimaryContainer,
                                    size: 28,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text('悬浮在头像右上角', style: theme.textTheme.bodySmall),
                        ],
                      ),

                      // 形态 C：包裹图标
                      Column(
                        children: [
                          SizedBox(
                            height: 60,
                            child: Center(
                              child: AppBadge(
                                count: _count,
                                dot: _dot,
                                maxCount: _maxCount,
                                showZero: _showZero,
                                size: _size,
                                color: _color,
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.notifications_rounded,
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text('悬浮在图标卡片', style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── 2. 经典跳跃动效快捷测试 ─────────────────────────────────────
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.animation_rounded, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text(
                        '经典滚轮与进退场动画测试',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber.shade100,
                          foregroundColor: Colors.brown.shade900,
                        ),
                        onPressed: () => _setCount(20, '19 → 20 (十位1->2,个位9->0)'),
                        child: const Text('19 → 20 ★核心滚轮'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber.shade100,
                          foregroundColor: Colors.brown.shade900,
                        ),
                        onPressed: () => _setCount(19, '20 → 19 (反向滚回)'),
                        child: const Text('20 → 19 ★反向滚轮'),
                      ),
                      FilledButton.tonal(
                        onPressed: () => _setCount(10, '9 → 10 (位数展开)'),
                        child: const Text('9 → 10 (位展开)'),
                      ),
                      FilledButton.tonal(
                        onPressed: () => _setCount(9, '10 → 9 (位数收缩)'),
                        child: const Text('10 → 9 (位收缩)'),
                      ),
                      FilledButton.tonal(
                        onPressed: () => _setCount(100, '99 → 100 (溢出99+)'),
                        child: const Text('99 → 100 (99+)'),
                      ),
                      FilledButton.tonal(
                        onPressed: () => _setCount(99, '100 → 99 (恢复两位)'),
                        child: const Text('100 → 99'),
                      ),
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green.shade100,
                          foregroundColor: Colors.green.shade900,
                        ),
                        onPressed: () => _setCount(1, '0 → 1 (弹性出现)'),
                        child: const Text('0 → 1 (弹出动效)'),
                      ),
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red.shade100,
                          foregroundColor: Colors.red.shade900,
                        ),
                        onPressed: () => _setCount(0, '1 → 0 (缩放淡出)'),
                        child: const Text('1 → 0 (隐藏动效)'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── 3. 步进微调与控制器 ──────────────────────────────────────────
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '数值微调控制',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _setCount(_count - 10, '-10'),
                        icon: const Icon(Icons.fast_rewind_rounded),
                        label: const Text('-10'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => _setCount(_count - 1, '-1'),
                        icon: const Icon(Icons.remove_rounded),
                        label: const Text('-1'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Center(
                          child: Text(
                            '$_count',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: _color,
                            ),
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _setCount(_count + 1, '+1'),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('+1'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => _setCount(_count + 10, '+10'),
                        icon: const Icon(Icons.fast_forward_rounded),
                        label: const Text('+10'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  // 配置开关
                  SwitchListTile(
                    title: const Text('小红点模式 (dot)'),
                    subtitle: const Text('不展示数字，仅展示小圆红点'),
                    value: _dot,
                    onChanged: (v) {
                      setState(() => _dot = v);
                      _recordLog('切换 dot: $v');
                    },
                  ),
                  SwitchListTile(
                    title: const Text('显示 0 (showZero)'),
                    subtitle: const Text('当数值为 0 时是否保留展示'),
                    value: _showZero,
                    onChanged: (v) {
                      setState(() => _showZero = v);
                      _recordLog('切换 showZero: $v');
                    },
                  ),
                  ListTile(
                    title: const Text('尺寸大小 (size)'),
                    trailing: SegmentedButton<AppBadgeSize>(
                      segments: const [
                        ButtonSegment(
                          value: AppBadgeSize.normal,
                          label: Text('标准 (20px)'),
                        ),
                        ButtonSegment(
                          value: AppBadgeSize.small,
                          label: Text('小型 (16px)'),
                        ),
                      ],
                      selected: {_size},
                      onSelectionChanged: (set) {
                        setState(() => _size = set.first);
                        _recordLog('切换 size: ${_size.name}');
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── 4. 执行状态与变动日志 ────────────────────────────────────────
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '变动与执行日志',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _log.clear()),
                        child: const Text('清空日志'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 140,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.4,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: theme.dividerColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child:
                        _log.isEmpty
                            ? const Center(
                              child: Text(
                                '暂无操作日志，点击上方按钮触发动效',
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                            : ListView.builder(
                              itemCount: _log.length,
                              itemBuilder:
                                  (context, index) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 2,
                                    ),
                                    child: Text(
                                      _log[index],
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
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
