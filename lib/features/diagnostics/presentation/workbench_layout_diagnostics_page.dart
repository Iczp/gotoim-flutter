import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../workbench/application/workbench_layout_notifier.dart';
import '../../workbench/domain/workbench_grid_item.dart';
import '../../workbench/presentation/widgets/folder_bubble_dialog.dart';
import '../../workbench/presentation/widgets/workbench_canvas.dart';

/// 开发诊断中心 - 工作台二维 Widget 布局引擎测试页面
class WorkbenchLayoutDiagnosticsPage extends ConsumerStatefulWidget {
  const WorkbenchLayoutDiagnosticsPage({super.key});

  @override
  ConsumerState<WorkbenchLayoutDiagnosticsPage> createState() =>
      _WorkbenchLayoutDiagnosticsPageState();
}

class _WorkbenchLayoutDiagnosticsPageState
    extends ConsumerState<WorkbenchLayoutDiagnosticsPage> {
  int _lastPackDurationMs = 0;
  String _lastActionLog = '就绪';

  void _recordTiming(VoidCallback action, String actionName) {
    final sw = Stopwatch()..start();
    action();
    sw.stop();
    setState(() {
      _lastPackDurationMs = sw.elapsedMilliseconds;
      _lastActionLog = '$actionName 完成 (耗时: ${sw.elapsedMilliseconds} ms)';
    });
  }

  void _addQuickItem(WorkbenchGridItemType type, int spanX, int spanY, {bool edgeToEdge = false}) {
    final notifier = ref.read(workbenchLayoutProvider.notifier);
    final now = DateTime.now().millisecondsSinceEpoch % 10000;

    WorkbenchGridItem item;
    switch (type) {
      case WorkbenchGridItemType.app:
        item = WorkbenchGridItem(
          id: 'test_app_$now',
          title: '测试应用$now',
          type: type,
          x: 0,
          y: 0,
          spanX: spanX,
          spanY: spanY,
          extra: {'icon': 'business', 'color': 0xFF1976D2},
        );
        break;
      case WorkbenchGridItemType.banner:
        item = WorkbenchGridItem(
          id: 'test_banner_$now',
          title: '动态 Banner $now',
          type: type,
          x: 0,
          y: 0,
          spanX: spanX,
          spanY: spanY,
          edgeToEdge: edgeToEdge,
          extra: {
            'subtitle': '自适应装箱混排测试横幅',
            'actionText': '立即体验',
          },
        );
        break;
      case WorkbenchGridItemType.cardWidget:
        item = WorkbenchGridItem(
          id: 'test_card_$now',
          title: '动态卡片 $now',
          type: type,
          x: 0,
          y: 0,
          spanX: spanX,
          spanY: spanY,
          extra: {
            'subtitle': '胶囊/中型卡片测试',
            'stat1Label': '指标A',
            'stat1Value': '$now',
            'stat2Label': '指标B',
            'stat2Value': '99',
          },
        );
        break;
      case WorkbenchGridItemType.folder:
        item = WorkbenchGridItem(
          id: 'test_folder_$now',
          title: '测试文件夹 $now',
          type: type,
          x: 0,
          y: 0,
          spanX: spanX,
          spanY: spanY,
          children: [
            WorkbenchGridItem(
              id: 'child_${now}_1',
              title: '子应用1',
              type: WorkbenchGridItemType.app,
              x: 0,
              y: 0,
              extra: {'icon': 'calendar_today', 'color': 0xFFF57C00},
            ),
            WorkbenchGridItem(
              id: 'child_${now}_2',
              title: '子应用2',
              type: WorkbenchGridItemType.app,
              x: 1,
              y: 0,
              extra: {'icon': 'email', 'color': 0xFFD32F2F},
            ),
          ],
        );
        break;
      case WorkbenchGridItemType.custom:
        item = WorkbenchGridItem(
          id: 'test_custom_$now',
          title: '自定义组件 $now',
          type: type,
          x: 0,
          y: 0,
          spanX: spanX,
          spanY: spanY,
        );
        break;
    }

    _recordTiming(() => notifier.addItem(item), '添加 ${spanX}x$spanY ${type.name}');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workbenchLayoutProvider);
    final notifier = ref.read(workbenchLayoutProvider.notifier);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final totalRows = notifier.engine.calculateTotalRows(state.items);
    final matrix = notifier.engine.computeOccupancyMatrix(state.items);

    return Scaffold(
      appBar: AppBar(
        title: const Text('工作台二维布局引擎诊断'),
        actions: [
          IconButton(
            tooltip: state.isEditing ? '退出编辑' : '编辑桌面',
            icon: Icon(
              state.isEditing ? Icons.check_circle : Icons.edit_note,
              color: state.isEditing ? colorScheme.primary : null,
            ),
            onPressed: notifier.toggleEditMode,
          ),
          IconButton(
            tooltip: '恢复默认桌面',
            icon: const Icon(Icons.restore),
            onPressed: () {
              _recordTiming(notifier.resetToDefaultLayout, '恢复默认布局');
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // 1. 平台支持与运行指标
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
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
                            '引擎状态指标',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '全平台支持: Android/iOS/iPad/Win/Mac/Web',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        children: [
                          _buildMetricPill(
                            label: '栅格列数',
                            value: '4 列',
                            color: colorScheme.primary,
                          ),
                          _buildMetricPill(
                            label: '组件总数',
                            value: '${state.items.length} 个',
                            color: colorScheme.secondary,
                          ),
                          _buildMetricPill(
                            label: '占用行数',
                            value: '$totalRows 行',
                            color: colorScheme.tertiary,
                          ),
                          _buildMetricPill(
                            label: '最近计算耗时',
                            value: '$_lastPackDurationMs ms',
                            color: Colors.teal,
                          ),
                          _buildMetricPill(
                            label: '模式',
                            value: state.isEditing ? '编辑排序' : '浏览交互',
                            color: state.isEditing ? Colors.orange : Colors.blueGrey,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '执行状态：$_lastActionLog',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // 2. 插入测试组件控制面板
              Text(
                '快捷测试：多尺寸组件装箱插入',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.apps, size: 16),
                    label: const Text('+ 1x1 App'),
                    onPressed: () => _addQuickItem(WorkbenchGridItemType.app, 1, 1),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.view_headline, size: 16),
                    label: const Text('+ 2x1 胶囊卡片'),
                    onPressed: () => _addQuickItem(WorkbenchGridItemType.cardWidget, 2, 1),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.dashboard, size: 16),
                    label: const Text('+ 2x2 中卡片'),
                    onPressed: () => _addQuickItem(WorkbenchGridItemType.cardWidget, 2, 2),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.campaign, size: 16),
                    label: const Text('+ 4x1 通栏通知'),
                    onPressed: () => _addQuickItem(WorkbenchGridItemType.banner, 4, 1),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.fullscreen, size: 16),
                    label: const Text('+ 4x2 贴边 Banner'),
                    onPressed: () => _addQuickItem(WorkbenchGridItemType.banner, 4, 2, edgeToEdge: true),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.folder, size: 16),
                    label: const Text('+ 文件夹'),
                    onPressed: () => _addQuickItem(WorkbenchGridItemType.folder, 1, 1),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // 3. 实时 4-Column 栅格矩阵占用查看器
              Text(
                '四列栅格占用矩阵 (Cell Matrix Inspector)',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: matrix.isEmpty
                    ? const Center(child: Text('暂无栅格数据'))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: List.generate(matrix.length, (rowIdx) {
                          final row = matrix[rowIdx];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 48,
                                  child: Text(
                                    'R$rowIdx:',
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                for (int colIdx = 0; colIdx < 4; colIdx++)
                                  Expanded(
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 2,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 4,
                                        horizontal: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: row[colIdx] != null
                                            ? colorScheme.primaryContainer
                                            : Colors.grey.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        row[colIdx] != null
                                            ? (row[colIdx]!.length > 8
                                                ? row[colIdx]!.substring(0, 8)
                                                : row[colIdx]!)
                                            : '空',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontFamily: 'monospace',
                                          color: row[colIdx] != null
                                              ? colorScheme.onPrimaryContainer
                                              : Colors.grey,
                                        ),
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }),
                      ),
              ),

              const SizedBox(height: 16),

              // 4. 实时画布模拟沙盒
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '实时桌面交互沙盒',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    state.isEditing ? '长按/拖拽卡片测试避让' : '点击右上角图标进入编辑',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                height: 520,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: colorScheme.outlineVariant,
                    width: 1.5,
                  ),
                ),
                child: WorkbenchCanvas(
                  onOpenApp: (item) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('触发启动: ${item.title} (${item.id})'),
                        duration: const Duration(milliseconds: 900),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 16),

              // 5. JSON 布局导出与复制
              ExpansionTile(
                title: const Text('当前桌面布局 JSON'),
                subtitle: Text('共 ${state.items.length} 项组件'),
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      const JsonEncoder.withIndent('  ').convert(
                        state.items.map((e) => e.toJson()).toList(),
                      ),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ),
                  OverflowBar(
                    alignment: MainAxisAlignment.end,
                    children: [
                      FilledButton.icon(
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('复制 JSON'),
                        onPressed: () {
                          final jsonStr = const JsonEncoder.withIndent('  ').convert(
                            state.items.map((e) => e.toJson()).toList(),
                          );
                          Clipboard.setData(ClipboardData(text: jsonStr));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已复制布局 JSON 到剪贴板')),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 32),
            ],
          ),

          // Folder modal
          if (state.openFolder != null)
            FolderBubbleDialog(
              folder: state.openFolder!,
              onClose: notifier.closeFolderBubble,
              onLaunchApp: (item) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('启动子应用: ${item.title}')),
                );
              },
              onUnpackApp: (childId) {
                notifier.unpackFromFolder(state.openFolder!.id, childId);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildMetricPill({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color.withValues(alpha: 0.8),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
