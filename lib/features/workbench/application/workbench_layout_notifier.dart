import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/workbench_repository.dart';
import '../domain/workbench_grid_item.dart';
import '../domain/workbench_layout_engine.dart';
import 'workbench_layout_state.dart';

/// Notifier providing state management and interactive operations for the
/// 2D workbench widget desktop.
class WorkbenchLayoutNotifier extends Notifier<WorkbenchLayoutState> {
  final WorkbenchLayoutEngine engine = const WorkbenchLayoutEngine();

  List<WorkbenchGridItem>? _originalItemsBeforeDrag;
  Timer? _folderMergeTimer;
  String? _potentialMergeTargetId;

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
    _folderMergeTimer?.cancel();
    _potentialMergeTargetId = null;
    _originalItemsBeforeDrag = null;

    state = state.copyWith(
      isEditing: next,
      clearDragging: true,
      clearTargetSlot: true,
      clearFolderMergeTarget: true,
    );
  }

  /// Start dragging an item by its [id].
  void startDragging(String id) {
    _folderMergeTimer?.cancel();
    _potentialMergeTargetId = null;
    _originalItemsBeforeDrag = List<WorkbenchGridItem>.from(state.items);

    final itemIndex = _originalItemsBeforeDrag!.indexWhere((e) => e.id == id);
    final initialRect =
        itemIndex != -1 ? _originalItemsBeforeDrag![itemIndex].rect : null;

    state = state.copyWith(
      draggingItemId: id,
      targetSlot: initialRect,
      clearFolderMergeTarget: true,
    );
  }

  /// Update drag hover position with target grid coordinates [targetX, targetY].
  void updateDragHover({required int targetX, required int targetY}) {
    if (state.draggingItemId == null || _originalItemsBeforeDrag == null) return;

    final dragId = state.draggingItemId!;
    final dragItem = _originalItemsBeforeDrag!.firstWhere(
      (e) => e.id == dragId,
      orElse: () => state.items.firstWhere((e) => e.id == dragId),
    );

    final cleanX = targetX.clamp(0, WorkbenchLayoutEngine.columns - dragItem.spanX);
    final cleanY = targetY < 0 ? 0 : targetY;

    // Check if hovering over an item that can merge into a folder
    WorkbenchGridItem? hitItem;
    for (final item in _originalItemsBeforeDrag!) {
      if (item.id != dragItem.id && item.rect.containsCell(cleanX, cleanY)) {
        hitItem = item;
        break;
      }
    }

    if (hitItem != null && engine.canMergeIntoFolder(dragItem, hitItem)) {
      if (_potentialMergeTargetId != hitItem.id) {
        _potentialMergeTargetId = hitItem.id;
        _folderMergeTimer?.cancel();
        _folderMergeTimer = Timer(const Duration(milliseconds: 380), () {
          if (state.draggingItemId != null && _potentialMergeTargetId == hitItem!.id) {
            HapticFeedback.mediumImpact(); // Vibration when folder merge preview triggers
            state = state.copyWith(
              folderMergeTargetId: hitItem.id,
              targetSlot: hitItem.rect,
            );
          }
        });
      }

      if (state.folderMergeTargetId != null) {
        return;
      }
    } else {
      _potentialMergeTargetId = null;
      _folderMergeTimer?.cancel();
      if (state.folderMergeTargetId != null) {
        state = state.copyWith(clearFolderMergeTarget: true);
      }
    }

    // Reorder and pack from the clean original layout
    final reorderedAndPacked = engine.reorderAndPack(
      items: _originalItemsBeforeDrag!,
      dragId: dragItem.id,
      targetX: cleanX,
      targetY: cleanY,
    );

    WorkbenchGridItem? newDragItem;
    try {
      newDragItem = reorderedAndPacked.firstWhere((e) => e.id == dragItem.id);
    } catch (_) {
      newDragItem = null;
    }

    final newSlot = newDragItem?.rect;
    if (newSlot != null && newSlot != state.targetSlot) {
      HapticFeedback.selectionClick(); // Vibration feedback when slot shifts!
    }

    state = state.copyWith(
      items: reorderedAndPacked,
      targetSlot: newSlot,
      clearFolderMergeTarget: true,
    );
  }

  /// Drop the currently dragged item and commit changes.
  void dropItem() {
    _folderMergeTimer?.cancel();
    _potentialMergeTargetId = null;
    HapticFeedback.mediumImpact(); // Vibration feedback when dropped!

    final dragId = state.draggingItemId;
    if (dragId == null) {
      cancelDrag();
      return;
    }

    // 1. Folder Merge Commit
    if (state.folderMergeTargetId != null) {
      final targetId = state.folderMergeTargetId!;
      final baseIndex = state.items.indexWhere((e) => e.id == targetId);
      final dragIndex = state.items.indexWhere((e) => e.id == dragId);

      if (baseIndex != -1 && dragIndex != -1) {
        final targetItem = state.items[baseIndex];
        final dragItem = state.items[dragIndex];
        final newFolder = engine.mergeIntoFolder(
          baseItem: targetItem,
          droppedItem: dragItem,
        );

        final updatedItems = state.items
            .where((e) => e.id != dragId && e.id != targetId)
            .toList()
          ..insert(baseIndex > dragIndex ? baseIndex - 1 : baseIndex, newFolder);

        final packed = engine.packItems(updatedItems);
        _originalItemsBeforeDrag = null;

        state = state.copyWith(
          items: packed,
          clearDragging: true,
          clearTargetSlot: true,
          clearFolderMergeTarget: true,
        );
        return;
      }
    }

    // 2. Normal Slot Drop Commit
    // The items in state.items are ALREADY the correctly reordered and packed layout!
    _originalItemsBeforeDrag = null;

    state = state.copyWith(
      clearDragging: true,
      clearTargetSlot: true,
      clearFolderMergeTarget: true,
    );
  }

  /// Cancel current drag operation.
  void cancelDrag() {
    _folderMergeTimer?.cancel();
    _potentialMergeTargetId = null;

    if (_originalItemsBeforeDrag != null) {
      state = state.copyWith(
        items: _originalItemsBeforeDrag,
        clearDragging: true,
        clearTargetSlot: true,
        clearFolderMergeTarget: true,
      );
      _originalItemsBeforeDrag = null;
    } else {
      state = state.copyWith(
        clearDragging: true,
        clearTargetSlot: true,
        clearFolderMergeTarget: true,
      );
    }
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
    _folderMergeTimer?.cancel();
    _potentialMergeTargetId = null;
    _originalItemsBeforeDrag = null;

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
