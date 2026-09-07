import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/workbench_repository.dart';
import '../domain/workbench_grid_item.dart';
import '../domain/workbench_layout_engine.dart';
import 'workbench_layout_state.dart';

/// Notifier providing state management and interactive operations for the
/// 2D workbench widget desktop.
class WorkbenchLayoutNotifier extends Notifier<WorkbenchLayoutState> {
  final WorkbenchLayoutEngine engine = const WorkbenchLayoutEngine();

  @override
  WorkbenchLayoutState build() {
    Future.microtask(_initLayout);
    return WorkbenchLayoutState(
      items: engine.packItems(createDefaultPreset()),
    );
  }

  /// Default mock items if repository has no saved layout.
  static List<WorkbenchGridItem> createDefaultPreset() {
    return [
      // 4x2 Edge-to-edge Hero Banner
      const WorkbenchGridItem(
        id: 'banner_hero',
        title: '欢迎来到 GotoIM 智能工作台',
        type: WorkbenchGridItemType.banner,
        x: 0,
        y: 0,
        spanX: 4,
        spanY: 2,
        edgeToEdge: true,
        extra: {
          'subtitle': '企业级全景协作与微应用引擎已就绪',
          'actionText': '立即体验',
          'imageUrl': 'https://picsum.photos/800/400',
        },
      ),

      // 1x1 Core Apps row
      const WorkbenchGridItem(
        id: 'app_oa',
        title: '协同办公',
        type: WorkbenchGridItemType.app,
        x: 0,
        y: 2,
        extra: {'icon': 'business', 'color': 0xFF1976D2},
      ),
      const WorkbenchGridItem(
        id: 'app_approval',
        title: '审批中心',
        type: WorkbenchGridItemType.app,
        x: 1,
        y: 2,
        extra: {'icon': 'verified_user', 'color': 0xFF388E3C, 'badge': '3'},
      ),
      const WorkbenchGridItem(
        id: 'app_calendar',
        title: '日程会议',
        type: WorkbenchGridItemType.app,
        x: 2,
        y: 2,
        extra: {'icon': 'calendar_today', 'color': 0xFFF57C00},
      ),

      // 1x1 Folder containing sub apps
      const WorkbenchGridItem(
        id: 'folder_tools',
        title: '效率工具',
        type: WorkbenchGridItemType.folder,
        x: 3,
        y: 2,
        children: [
          WorkbenchGridItem(
            id: 'sub_calc',
            title: '云盘存储',
            type: WorkbenchGridItemType.app,
            x: 0,
            y: 0,
            extra: {'icon': 'cloud_queue', 'color': 0xFF0288D1},
          ),
          WorkbenchGridItem(
            id: 'sub_notes',
            title: '速记灵感',
            type: WorkbenchGridItemType.app,
            x: 1,
            y: 0,
            extra: {'icon': 'edit_note', 'color': 0xFF7B1FA2},
          ),
          WorkbenchGridItem(
            id: 'sub_scan',
            title: '统一识码',
            type: WorkbenchGridItemType.app,
            x: 2,
            y: 0,
            extra: {'icon': 'qr_code_scanner', 'color': 0xFF00796B},
          ),
          WorkbenchGridItem(
            id: 'sub_todo',
            title: '个人待办',
            type: WorkbenchGridItemType.app,
            x: 3,
            y: 0,
            extra: {'icon': 'check_circle_outline', 'color': 0xFFE64A19},
          ),
        ],
      ),

      // 2x2 Dashboard Card Widget
      const WorkbenchGridItem(
        id: 'widget_stats',
        title: '今日业务简报',
        type: WorkbenchGridItemType.cardWidget,
        x: 0,
        y: 3,
        spanX: 2,
        spanY: 2,
        extra: {
          'stat1Label': '进行中项目',
          'stat1Value': '12',
          'stat2Label': '待审单据',
          'stat2Value': '5',
        },
      ),

      // 2x1 Horizontal Capsule Widget
      const WorkbenchGridItem(
        id: 'widget_quick_clock',
        title: '考勤打卡',
        type: WorkbenchGridItemType.cardWidget,
        x: 2,
        y: 3,
        spanX: 2,
        spanY: 1,
        extra: {
          'subtitle': '09:00 上班打卡成功',
          'icon': 'fingerprint',
          'color': 0xFF43A047,
        },
      ),

      // Two 1x1 apps filling row 4
      const WorkbenchGridItem(
        id: 'app_mail',
        title: '企业邮箱',
        type: WorkbenchGridItemType.app,
        x: 2,
        y: 4,
        extra: {'icon': 'email', 'color': 0xFFD32F2F},
      ),
      const WorkbenchGridItem(
        id: 'app_contact',
        title: '组织架构',
        type: WorkbenchGridItemType.app,
        x: 3,
        y: 4,
        extra: {'icon': 'people', 'color': 0xFF512DA8},
      ),

      // 4x1 Announcement Banner (non edge-to-edge, nested between apps)
      const WorkbenchGridItem(
        id: 'banner_notice',
        title: '系统通知：本周五晚将进行服务器维护升级',
        type: WorkbenchGridItemType.banner,
        x: 0,
        y: 5,
        spanX: 4,
        spanY: 1,
        edgeToEdge: false,
        extra: {
          'icon': 'campaign',
          'color': 0xFFE65100,
        },
      ),
    ];
  }

  Future<void> _initLayout() async {
    try {
      final repository = ref.read(workbenchRepositoryProvider);
      final remoteApps = await repository.getApps();
      if (remoteApps.isNotEmpty) {
        // Merge real backend apps into our preset
        final preset = createDefaultPreset();
        final existingAppIds = preset.map((e) => e.id).toSet();

        final extraGridApps = <WorkbenchGridItem>[];
        for (final app in remoteApps) {
          if (!existingAppIds.contains(app.appId)) {
            extraGridApps.add(
              WorkbenchGridItem(
                id: app.appId,
                title: app.name,
                type: WorkbenchGridItemType.app,
                x: 0,
                y: 0,
                appPayload: app,
                extra: {
                  'iconUrl': app.iconUrl,
                },
              ),
            );
          }
        }

        final allItems = [...preset, ...extraGridApps];
        final packed = engine.packItems(allItems);
        state = state.copyWith(items: packed);
      } else {
        final packed = engine.packItems(createDefaultPreset());
        state = state.copyWith(items: packed);
      }
    } catch (_) {
      final packed = engine.packItems(createDefaultPreset());
      state = state.copyWith(items: packed);
    }
  }

  /// Toggle desktop edit mode.
  void toggleEditMode([bool? force]) {
    final next = force ?? !state.isEditing;
    state = state.copyWith(
      isEditing: next,
      clearDragging: true,
      clearTargetSlot: true,
      clearFolderMergeTarget: true,
    );
  }

  /// Start dragging an item by its [id].
  void startDragging(String id) {
    state = state.copyWith(
      draggingItemId: id,
      clearTargetSlot: true,
      clearFolderMergeTarget: true,
    );
  }

  /// Update drag hover position with target grid coordinates [targetX, targetY].
  void updateDragHover({required int targetX, required int targetY}) {
    final dragItem = state.draggingItem;
    if (dragItem == null) return;

    final cleanX = targetX.clamp(0, WorkbenchLayoutEngine.columns - dragItem.spanX);
    final cleanY = targetY < 0 ? 0 : targetY;

    // Check if hovering over another item that can be merged into a folder
    WorkbenchGridItem? candidateMerge;
    for (final item in state.items) {
      if (item.id != dragItem.id &&
          item.rect.containsCell(cleanX, cleanY) &&
          engine.canMergeIntoFolder(dragItem, item)) {
        candidateMerge = item;
        break;
      }
    }

    if (candidateMerge != null) {
      state = state.copyWith(
        folderMergeTargetId: candidateMerge.id,
        targetSlot: candidateMerge.rect,
      );
      return;
    }

    // Normal slot displacement preview
    final displaced = engine.previewDisplacement(
      items: state.items,
      dragItem: dragItem,
      targetX: cleanX,
      targetY: cleanY,
    );

    // Keep dragged item at target position in preview
    final previewItems = <WorkbenchGridItem>[
      ...displaced,
      dragItem.copyWith(
        x: cleanX,
        y: cleanY,
      ),
    ];

    state = state.copyWith(
      items: previewItems,
      clearFolderMergeTarget: true,
      targetSlot: GridRect(
        x: cleanX,
        y: cleanY,
        spanX: dragItem.spanX,
        spanY: dragItem.spanY,
      ),
    );
  }

  /// Drop the currently dragged item and commit changes.
  void dropItem() {
    final dragItem = state.draggingItem;
    if (dragItem == null) {
      cancelDrag();
      return;
    }

    // 1. Folder Merge
    if (state.folderMergeTargetId != null) {
      final targetId = state.folderMergeTargetId!;
      final targetIndex = state.items.indexWhere((e) => e.id == targetId);
      if (targetIndex != -1) {
        final targetItem = state.items[targetIndex];
        final newFolder = engine.mergeIntoFolder(
          baseItem: targetItem,
          droppedItem: dragItem,
        );

        final updatedItems = state.items
            .where((e) => e.id != dragItem.id && e.id != targetId)
            .toList()
          ..insert(targetIndex, newFolder);

        final packed = engine.packItems(updatedItems);
        state = state.copyWith(
          items: packed,
          clearDragging: true,
          clearTargetSlot: true,
          clearFolderMergeTarget: true,
        );
        return;
      }
    }

    // 2. Normal slot drop
    final packed = engine.packItems(state.items);
    state = state.copyWith(
      items: packed,
      clearDragging: true,
      clearTargetSlot: true,
      clearFolderMergeTarget: true,
    );
  }

  /// Cancel current drag operation.
  void cancelDrag() {
    state = state.copyWith(
      clearDragging: true,
      clearTargetSlot: true,
      clearFolderMergeTarget: true,
    );
  }

  /// Adds a new widget item and automatically packs it into the layout.
  void addItem(WorkbenchGridItem item) {
    final updated = [...state.items, item];
    final packed = engine.packItems(updated);
    state = state.copyWith(items: packed);
  }

  /// Removes an item from the layout by its [id].
  void removeItem(String id) {
    final updated = state.items.where((e) => e.id != id).toList();
    final packed = engine.packItems(updated);
    state = state.copyWith(items: packed);
  }

  /// Opens the expanded floating bubble for [folder].
  void openFolderBubble(WorkbenchGridItem folder) {
    state = state.copyWith(openFolder: folder);
  }

  /// Closes the folder floating bubble.
  void closeFolderBubble() {
    state = state.copyWith(clearOpenFolder: true);
  }

  /// Unpacks [childId] from folder [folderId] onto the main grid.
  void unpackFromFolder(String folderId, String childId) {
    final folderIndex = state.items.indexWhere((e) => e.id == folderId);
    if (folderIndex == -1) return;

    final folder = state.items[folderIndex];
    final result = engine.unpackItemFromFolder(
      folder: folder,
      childId: childId,
    );

    final updated = List<WorkbenchGridItem>.from(state.items);
    if (result.updatedFolder != null) {
      updated[folderIndex] = result.updatedFolder!;
    } else {
      updated.removeAt(folderIndex);
    }

    updated.add(result.unpackedItem);
    final packed = engine.packItems(updated);

    state = state.copyWith(
      items: packed,
      openFolder: result.updatedFolder,
    );
  }

  /// Resets to default initial preset.
  void resetToDefaultLayout() {
    final packed = engine.packItems(createDefaultPreset());
    state = state.copyWith(
      items: packed,
      isEditing: false,
      clearDragging: true,
      clearTargetSlot: true,
      clearFolderMergeTarget: true,
      clearOpenFolder: true,
    );
  }
}

/// Riverpod provider for workbench desktop layout state and operations.
final workbenchLayoutProvider =
    NotifierProvider<WorkbenchLayoutNotifier, WorkbenchLayoutState>(
      WorkbenchLayoutNotifier.new,
    );
