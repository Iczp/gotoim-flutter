import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/deep_link/deep_link_service.dart';
import '../../../core/services/task/app_task_manager.dart';
import '../application/workbench_layout_notifier.dart';
import '../data/workbench_models.dart';
import '../domain/workbench_grid_item.dart';
import 'widgets/folder_bubble_dialog.dart';
import 'widgets/workbench_canvas.dart';

/// The 2D desktop workbench tab page.
///
/// Features:
/// 1. 4-column multi-size 2D grid layout ($1\times 1$, $2\times 1$, $2\times 2$, $4\times 1$, $4\times 2$).
/// 2. Edge-to-edge full bleed and interleaved banners.
/// 3. Folder containers with miniature preview and interactive popup bubble.
/// 4. 2D drag-and-drop rearrangement with collision displacement & bin-packing.
/// 5. Uniform deep link and independent system task launch modes.
class WorkbenchPage extends ConsumerStatefulWidget {
  const WorkbenchPage({super.key});

  @override
  ConsumerState<WorkbenchPage> createState() => _WorkbenchPageState();
}

class _WorkbenchPageState extends ConsumerState<WorkbenchPage> {
  bool _useDeepLinkMode = false;

  Future<void> _openAppDirect(WorkbenchApp app) async {
    try {
      final taskManager = ref.read(appTaskManagerProvider);
      await openWorkbenchApp(
        app,
        taskManager: taskManager,
        navigator: Navigator.of(context),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('打开 ${app.name} 失败：$e')));
      }
    }
  }

  Future<void> _openAppViaDeepLink(WorkbenchApp app) async {
    final deepLinkUri = Uri.parse('gotoim-dev://workbench/${app.appId}');
    try {
      final service = ref.read(deepLinkServiceProvider);
      final result = await service.handleUri(
        deepLinkUri,
        source: 'workbench_ui',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Deep Link 响应 (${result.status.name}): ${result.message}',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Deep Link 打开失败：$e')));
      }
    }
  }

  void _handleItemTap(WorkbenchGridItem item) {
    if (item.appPayload != null) {
      if (_useDeepLinkMode) {
        _openAppViaDeepLink(item.appPayload!);
      } else {
        _openAppDirect(item.appPayload!);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已启动：${item.title} (${item.type.name})'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _showAddWidgetSheet() {
    final notifier = ref.read(workbenchLayoutProvider.notifier);

    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final maxHeight = MediaQuery.of(context).size.height * 0.75;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '添加组件到工作台',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.add_to_home_screen),
                  ),
                  title: const Text('1x1 标准快捷应用'),
                  subtitle: const Text('标准单位格快捷入口'),
                  onTap: () {
                    Navigator.pop(context);
                    final now = DateTime.now().millisecondsSinceEpoch;
                    notifier.addItem(
                      WorkbenchGridItem(
                        id: 'custom_app_$now',
                        title: '新应用',
                        type: WorkbenchGridItemType.app,
                        x: 0,
                        y: 0,
                        extra: {'icon': 'apps', 'color': 0xFF009688},
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.view_stream_outlined),
                  ),
                  title: const Text('2x1 快捷胶囊卡片'),
                  subtitle: const Text('占两列一行的紧凑状态卡片'),
                  onTap: () {
                    Navigator.pop(context);
                    final now = DateTime.now().millisecondsSinceEpoch;
                    notifier.addItem(
                      WorkbenchGridItem(
                        id: 'custom_capsule_$now',
                        title: '快捷便签',
                        type: WorkbenchGridItemType.cardWidget,
                        x: 0,
                        y: 0,
                        spanX: 2,
                        spanY: 1,
                        extra: {
                          'subtitle': '随时记录业务待办',
                          'icon': 'widgets',
                        },
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.dashboard_outlined),
                  ),
                  title: const Text('2x2 中型数据卡片'),
                  subtitle: const Text('两行两列中型看板'),
                  onTap: () {
                    Navigator.pop(context);
                    final now = DateTime.now().millisecondsSinceEpoch;
                    notifier.addItem(
                      WorkbenchGridItem(
                        id: 'custom_card_$now',
                        title: '团队看板',
                        type: WorkbenchGridItemType.cardWidget,
                        x: 0,
                        y: 0,
                        spanX: 2,
                        spanY: 2,
                        extra: {
                          'stat1Label': '已完成',
                          'stat1Value': '19',
                          'stat2Label': '跟进中',
                          'stat2Value': '7',
                        },
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.campaign_outlined),
                  ),
                  title: const Text('4x1 通栏通知横幅'),
                  subtitle: const Text('占满4列全宽的单行公告条'),
                  onTap: () {
                    Navigator.pop(context);
                    final now = DateTime.now().millisecondsSinceEpoch;
                    notifier.addItem(
                      WorkbenchGridItem(
                        id: 'custom_notice_$now',
                        title: '温馨提示：本周例会时间调整为下午3点',
                        type: WorkbenchGridItemType.banner,
                        x: 0,
                        y: 0,
                        spanX: 4,
                        spanY: 1,
                        extra: {'icon': 'campaign'},
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.fullscreen),
                  ),
                  title: const Text('4x2 全屏贴边 Banner (无边距)'),
                  subtitle: const Text('占满4列全宽且无左右边距贴边展示'),
                  onTap: () {
                    Navigator.pop(context);
                    final now = DateTime.now().millisecondsSinceEpoch;
                    notifier.addItem(
                      WorkbenchGridItem(
                        id: 'custom_banner_$now',
                        title: '探索 GotoIM 企业数字化方案',
                        type: WorkbenchGridItemType.banner,
                        x: 0,
                        y: 0,
                        spanX: 4,
                        spanY: 2,
                        edgeToEdge: true,
                        extra: {
                          'subtitle': '一站式赋能企业协同与实时通讯',
                          'actionText': '查看详情',
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  }

  @override
  Widget build(BuildContext context) {
    final layoutState = ref.watch(workbenchLayoutProvider);
    final notifier = ref.read(workbenchLayoutProvider.notifier);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return PopScope(
      canPop: !layoutState.isEditing && layoutState.openFolder == null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (layoutState.openFolder != null) {
          notifier.closeFolderBubble();
          return;
        }
        if (layoutState.isEditing) {
          HapticFeedback.lightImpact();
          notifier.toggleEditMode(false);
          return;
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: layoutState.isEditing
              ? IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: '退出编辑',
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    notifier.toggleEditMode(false);
                  },
                )
              : null,
          title: Text(layoutState.isEditing ? '编辑工作台' : '工作台'),
          actions: [
          // Launch mode switcher
          Tooltip(
            message: _useDeepLinkMode ? '当前：Deep Link 唤醒模式' : '当前：直接启动模式',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _useDeepLinkMode ? Icons.link : Icons.open_in_new,
                  size: 16,
                  color: _useDeepLinkMode
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 2),
                Text(
                  _useDeepLinkMode ? 'DeepLink' : '常规',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: _useDeepLinkMode
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                Transform.scale(
                  scale: 0.75,
                  child: Switch(
                    value: _useDeepLinkMode,
                    onChanged: (val) => setState(() => _useDeepLinkMode = val),
                  ),
                ),
              ],
            ),
          ),

          // Edit mode toggle
          IconButton(
            tooltip: layoutState.isEditing ? '完成' : '编辑桌面',
            icon: Icon(
              layoutState.isEditing ? Icons.check_circle : Icons.tune_rounded,
              color: layoutState.isEditing ? colorScheme.primary : null,
            ),
            onPressed: () {
              HapticFeedback.lightImpact();
              notifier.toggleEditMode();
            },
          ),

          // More options menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (val) {
              if (val == 'add') {
                _showAddWidgetSheet();
              } else if (val == 'reset') {
                notifier.resetToDefaultLayout();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已恢复默认工作台桌面')),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'add',
                child: Row(
                  children: [
                    Icon(Icons.add_circle_outline, size: 20),
                    SizedBox(width: 8),
                    Text('添加小组件'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'reset',
                child: Row(
                  children: [
                    Icon(Icons.restore_outlined, size: 20),
                    SizedBox(width: 8),
                    Text('恢复预设桌面'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          // The 2D grid canvas
          WorkbenchCanvas(
            onOpenApp: _handleItemTap,
          ),

          // Folder floating bubble dialog
          if (layoutState.openFolder != null)
            FolderBubbleDialog(
              folder: layoutState.openFolder!,
              onClose: notifier.closeFolderBubble,
              onLaunchApp: _handleItemTap,
              onUnpackApp: (childId) {
                notifier.unpackFromFolder(
                  layoutState.openFolder!.id,
                  childId,
                );
              },
            ),
        ],
      ),
    ),
  );
}
}
