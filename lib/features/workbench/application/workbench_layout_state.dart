import '../domain/workbench_grid_item.dart';

/// State of the 2D workbench desktop layout and interaction.
class WorkbenchLayoutState {
  const WorkbenchLayoutState({
    required this.items,
    this.isEditing = false,
    this.draggingItemId,
    this.targetSlot,
    this.folderMergeTargetId,
    this.openFolder,
    this.isSaving = false,
  });

  /// All items currently placed on the 4-column workbench grid.
  final List<WorkbenchGridItem> items;

  /// Whether the workbench is in edit/reorder mode.
  final bool isEditing;

  /// The ID of the item currently being dragged.
  final String? draggingItemId;

  /// The active grid slot target where the placeholder indicator is previewed.
  final GridRect? targetSlot;

  /// Target item ID when hovering over an App/Folder to trigger folder merge preview.
  final String? folderMergeTargetId;

  /// The folder currently opened in the expanded floating bubble overlay.
  final WorkbenchGridItem? openFolder;

  /// Whether a save/persistence operation is running.
  final bool isSaving;

  WorkbenchGridItem? get draggingItem {
    if (draggingItemId == null) return null;
    try {
      return items.firstWhere((e) => e.id == draggingItemId);
    } catch (_) {
      return null;
    }
  }

  WorkbenchLayoutState copyWith({
    List<WorkbenchGridItem>? items,
    bool? isEditing,
    String? draggingItemId,
    GridRect? targetSlot,
    String? folderMergeTargetId,
    WorkbenchGridItem? openFolder,
    bool clearDragging = false,
    bool clearTargetSlot = false,
    bool clearFolderMergeTarget = false,
    bool clearOpenFolder = false,
    bool? isSaving,
  }) {
    return WorkbenchLayoutState(
      items: items ?? this.items,
      isEditing: isEditing ?? this.isEditing,
      draggingItemId:
          clearDragging ? null : (draggingItemId ?? this.draggingItemId),
      targetSlot: clearTargetSlot ? null : (targetSlot ?? this.targetSlot),
      folderMergeTargetId:
          clearFolderMergeTarget
              ? null
              : (folderMergeTargetId ?? this.folderMergeTargetId),
      openFolder: clearOpenFolder ? null : (openFolder ?? this.openFolder),
      isSaving: isSaving ?? this.isSaving,
    );
  }
}
