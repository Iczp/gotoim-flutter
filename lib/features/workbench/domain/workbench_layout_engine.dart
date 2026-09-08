import 'dart:math' as math;
import 'workbench_grid_item.dart';

/// Pure Dart 2D layout calculation engine for the 4-column workbench grid.
///
/// Provides:
/// 1. Compact Flow Bin-Packing (流式装箱)
/// 2. Collision displacement & reflow (碰撞排斥与链式避让)
/// 3. Folder merge & unpack detection (文件夹合并与解散)
/// 4. 2D occupancy matrix mapping for diagnostics and inspection
class WorkbenchLayoutEngine {
  const WorkbenchLayoutEngine();

  static const int columns = 4;

  /// Packs [items] into the 4-column grid using a 2D first-fit scanline algorithm.
  ///
  /// Preserves the order of [items]. Finds the earliest row [y] >= 0 and column
  /// [x] in [0, columns - item.spanX] where the rectangle does not collide with
  /// any previously placed item.
  List<WorkbenchGridItem> packItems(List<WorkbenchGridItem> items) {
    if (items.isEmpty) return const [];

    final occupied = <int, Set<int>>{}; // row -> set of occupied column indices
    final result = <WorkbenchGridItem>[];

    for (final item in items) {
      final spanX = item.spanX.clamp(1, columns);
      final spanY = math.max(1, item.spanY);

      int targetY = 0;
      int targetX = 0;
      bool placed = false;

      while (!placed) {
        for (int x = 0; x <= columns - spanX; x++) {
          if (_canFitAt(occupied, x, targetY, spanX, spanY)) {
            targetX = x;
            placed = true;
            break;
          }
        }
        if (!placed) {
          targetY++;
        }
      }

      // Mark cells as occupied
      _markOccupied(occupied, targetX, targetY, spanX, spanY);

      result.add(
        item.copyWith(
          x: targetX,
          y: targetY,
          spanX: spanX,
          spanY: spanY,
        ),
      );
    }

    return result;
  }

  /// Calculates a collision-free displacement layout while [dragItem] is
  /// hovering at [targetX, targetY].
  ///
  /// All other items in [items] that collide with [targetX, targetY, spanX, spanY]
  /// or with each other will be pushed to the earliest available free slot.
  List<WorkbenchGridItem> previewDisplacement({
    required List<WorkbenchGridItem> items,
    required WorkbenchGridItem dragItem,
    required int targetX,
    required int targetY,
  }) {
    final cleanTargetX = targetX.clamp(0, columns - dragItem.spanX);
    final cleanTargetY = math.max(0, targetY);
    final ghostRect = GridRect(
      x: cleanTargetX,
      y: cleanTargetY,
      spanX: dragItem.spanX,
      spanY: dragItem.spanY,
    );

    // Initial occupancy: ghost item occupies targetRect
    final occupied = <int, Set<int>>{};
    _markOccupied(
      occupied,
      ghostRect.x,
      ghostRect.y,
      ghostRect.spanX,
      ghostRect.spanY,
    );

    // Filter out the item being dragged
    final otherItems = items.where((e) => e.id != dragItem.id).toList();

    // Sort items by reading order (y * columns + x) so the reflow is stable
    otherItems.sort((a, b) {
      final orderA = a.y * columns + a.x;
      final orderB = b.y * columns + b.x;
      return orderA.compareTo(orderB);
    });

    final placedItems = <WorkbenchGridItem>[];

    for (final item in otherItems) {
      final spanX = item.spanX.clamp(1, columns);
      final spanY = math.max(1, item.spanY);

      // Prefer keeping original position if not colliding with ghost or other items
      if (_canFitAt(occupied, item.x, item.y, spanX, spanY)) {
        _markOccupied(occupied, item.x, item.y, spanX, spanY);
        placedItems.add(item);
      } else {
        // Find next nearest free slot starting from its current y or ghost y
        final startY = math.min(item.y, ghostRect.y);
        int freeX = 0;
        int freeY = startY;
        bool placed = false;

        while (!placed) {
          for (int x = 0; x <= columns - spanX; x++) {
            if (_canFitAt(occupied, x, freeY, spanX, spanY)) {
              freeX = x;
              placed = true;
              break;
            }
          }
          if (!placed) {
            freeY++;
          }
        }

        _markOccupied(occupied, freeX, freeY, spanX, spanY);
        placedItems.add(
          item.copyWith(
            x: freeX,
            y: freeY,
            spanX: spanX,
            spanY: spanY,
          ),
        );
      }
    }

    return placedItems;
  }

  /// Finds the item in [items] occupying the cell at ([targetX], [targetY]), if any.
  WorkbenchGridItem? findItemAtCell(
    List<WorkbenchGridItem> items,
    int targetX,
    int targetY,
  ) {
    for (final item in items) {
      if (item.rect.containsCell(targetX, targetY)) {
        return item;
      }
    }
    return null;
  }

  /// Reorders [items] by moving the item with [dragId] to the position of ([targetX], [targetY]),
  /// then calculates a collision-free displacement layout where non-colliding items keep their
  /// positions, and colliding items are cleanly displaced or swapped without scrambling the grid.
  List<WorkbenchGridItem> reorderAndPack({
    required List<WorkbenchGridItem> items,
    required String dragId,
    required int targetX,
    required int targetY,
  }) {
    final oldIndex = items.indexWhere((e) => e.id == dragId);
    if (oldIndex == -1) return items;

    final dragItem = items[oldIndex];
    final cleanTargetX = targetX.clamp(0, columns - dragItem.spanX);
    final cleanTargetY = math.max(0, targetY);
    final targetRect = GridRect(
      x: cleanTargetX,
      y: cleanTargetY,
      spanX: dragItem.spanX,
      spanY: dragItem.spanY,
    );

    if (dragItem.rect == targetRect) {
      return items;
    }

    // Special fast-path for 1x1 items on the same row (preserving reading order shift)
    if (dragItem.spanX == 1 && dragItem.spanY == 1) {
      final sameRowItems = items
          .where((e) => e.y == dragItem.y && e.spanX == 1 && e.spanY == 1)
          .toList();
      if (cleanTargetY == dragItem.y && sameRowItems.length > 1) {
        final hasTargetCell = sameRowItems.any((e) => e.x == cleanTargetX);
        if (hasTargetCell) {
          final minX = math.min(dragItem.x, cleanTargetX);
          final maxX = math.max(dragItem.x, cleanTargetX);
          final intermediateItems = sameRowItems
              .where((e) => e.x >= minX && e.x <= maxX)
              .toList();

          if (intermediateItems.length == (maxX - minX + 1)) {
            final result = <WorkbenchGridItem>[];
            final shiftForward = cleanTargetX > dragItem.x;

            for (final item in items) {
              if (item.id == dragId) {
                result.add(item.copyWith(x: cleanTargetX, y: cleanTargetY));
              } else if (item.y == dragItem.y && item.x >= minX && item.x <= maxX) {
                final newX = shiftForward ? item.x - 1 : item.x + 1;
                result.add(item.copyWith(x: newX));
              } else {
                result.add(item);
              }
            }

            result.sort((a, b) {
              final orderA = a.y * columns + a.x;
              final orderB = b.y * columns + b.x;
              return orderA.compareTo(orderB);
            });
            return result;
          }
        }
      }
    }

    // General 2D collision-displacement layout:
    // 1. Dragged item is placed at targetRect
    final occupied = <int, Set<int>>{};
    _markOccupied(
      occupied,
      targetRect.x,
      targetRect.y,
      targetRect.spanX,
      targetRect.spanY,
    );

    final placedDragItem = dragItem.copyWith(
      x: targetRect.x,
      y: targetRect.y,
      spanX: targetRect.spanX,
      spanY: targetRect.spanY,
    );

    // 2. Separate remaining items into non-colliding and colliding
    final otherItems = items.where((e) => e.id != dragId).toList();
    final nonColliding = <WorkbenchGridItem>[];
    final colliding = <WorkbenchGridItem>[];

    for (final item in otherItems) {
      if (item.rect.intersects(targetRect)) {
        colliding.add(item);
      } else {
        nonColliding.add(item);
      }
    }

    // Sort non-colliding items by reading order
    nonColliding.sort((a, b) {
      final orderA = a.y * columns + a.x;
      final orderB = b.y * columns + b.x;
      return orderA.compareTo(orderB);
    });

    // Mark non-colliding items in occupancy grid
    final stablePlaced = <WorkbenchGridItem>[];
    for (final item in nonColliding) {
      if (_canFitAt(occupied, item.x, item.y, item.spanX, item.spanY)) {
        _markOccupied(occupied, item.x, item.y, item.spanX, item.spanY);
        stablePlaced.add(item);
      } else {
        colliding.add(item);
      }
    }

    // 3. If single 1x1 colliding item and dragItem is 1x1, directly swap to dragItem's old spot if free
    if (colliding.length == 1 &&
        dragItem.spanX == 1 &&
        dragItem.spanY == 1 &&
        colliding.first.spanX == 1 &&
        colliding.first.spanY == 1) {
      final singleColliding = colliding.first;
      if (_canFitAt(occupied, dragItem.x, dragItem.y, 1, 1)) {
        _markOccupied(occupied, dragItem.x, dragItem.y, 1, 1);
        final swapped = singleColliding.copyWith(x: dragItem.x, y: dragItem.y);
        final result = [...stablePlaced, swapped, placedDragItem];
        result.sort((a, b) {
          final orderA = a.y * columns + a.x;
          final orderB = b.y * columns + b.x;
          return orderA.compareTo(orderB);
        });
        return result;
      }
    }

    // 4. Displace colliding items to nearest available free slots
    final displacedPlaced = <WorkbenchGridItem>[];
    for (final item in colliding) {
      final spanX = item.spanX.clamp(1, columns);
      final spanY = math.max(1, item.spanY);

      final startY = math.min(dragItem.y, item.y);
      int freeX = 0;
      int freeY = startY;
      bool placed = false;

      while (!placed) {
        for (int x = 0; x <= columns - spanX; x++) {
          if (_canFitAt(occupied, x, freeY, spanX, spanY)) {
            freeX = x;
            placed = true;
            break;
          }
        }
        if (!placed) {
          freeY++;
        }
      }

      _markOccupied(occupied, freeX, freeY, spanX, spanY);
      displacedPlaced.add(
        item.copyWith(
          x: freeX,
          y: freeY,
          spanX: spanX,
          spanY: spanY,
        ),
      );
    }

    final finalResult = [...stablePlaced, ...displacedPlaced, placedDragItem];
    finalResult.sort((a, b) {
      final orderA = a.y * columns + a.x;
      final orderB = b.y * columns + b.x;
      return orderA.compareTo(orderB);
    });

    return finalResult;
  }

  /// Whether [dragItem] can be merged into [targetItem] as a folder.
  ///
  /// True if:
  /// - [dragItem] and [targetItem] have distinct IDs.
  /// - [dragItem] is an App or Folder.
  /// - [targetItem] is an App or Folder.
  bool canMergeIntoFolder(WorkbenchGridItem dragItem, WorkbenchGridItem targetItem) {
    if (dragItem.id == targetItem.id) return false;
    final validDrag =
        dragItem.type == WorkbenchGridItemType.app ||
        dragItem.type == WorkbenchGridItemType.folder;
    final validTarget =
        targetItem.type == WorkbenchGridItemType.app ||
        targetItem.type == WorkbenchGridItemType.folder;
    return validDrag && validTarget;
  }

  /// Merges [droppedItem] into [baseItem], returning the created or updated Folder item.
  WorkbenchGridItem mergeIntoFolder({
    required WorkbenchGridItem baseItem,
    required WorkbenchGridItem droppedItem,
    String? folderTitle,
  }) {
    final children = <WorkbenchGridItem>[];

    // Collect baseItem children or baseItem itself
    if (baseItem.type == WorkbenchGridItemType.folder && baseItem.children != null) {
      children.addAll(baseItem.children!);
    } else {
      children.add(
        baseItem.copyWith(
          x: 0,
          y: 0,
          spanX: 1,
          spanY: 1,
        ),
      );
    }

    // Collect droppedItem children or droppedItem itself
    if (droppedItem.type == WorkbenchGridItemType.folder &&
        droppedItem.children != null) {
      children.addAll(droppedItem.children!);
    } else {
      children.add(
        droppedItem.copyWith(
          x: 0,
          y: 0,
          spanX: 1,
          spanY: 1,
        ),
      );
    }

    final title = folderTitle ??
        (baseItem.type == WorkbenchGridItemType.folder
            ? baseItem.title
            : '文件夹 (${children.length})');

    return WorkbenchGridItem(
      id: baseItem.type == WorkbenchGridItemType.folder
          ? baseItem.id
          : 'folder_${baseItem.id}_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      type: WorkbenchGridItemType.folder,
      x: baseItem.x,
      y: baseItem.y,
      spanX: baseItem.spanX,
      spanY: baseItem.spanY,
      children: children,
    );
  }

  /// Unpacks [childId] from [folder].
  ///
  /// Returns a record with:
  /// - `updatedFolder`: Updated folder item (or null if dissolved).
  /// - `unpackedItem`: The extracted item ready to be placed on the grid.
  ({WorkbenchGridItem? updatedFolder, WorkbenchGridItem unpackedItem})
      unpackItemFromFolder({
    required WorkbenchGridItem folder,
    required String childId,
  }) {
    final children = List<WorkbenchGridItem>.from(folder.children ?? const []);
    final index = children.indexWhere((c) => c.id == childId);
    if (index == -1) {
      throw ArgumentError('Child with ID $childId not found in folder ${folder.id}');
    }

    final unpacked = children.removeAt(index);

    if (children.isEmpty) {
      return (updatedFolder: null, unpackedItem: unpacked);
    }

    // If only 1 child remains, dissolve folder or keep as folder based on preference
    final updatedFolder = folder.copyWith(
      title: folder.title.startsWith('文件夹') ? '文件夹 (${children.length})' : folder.title,
      children: children,
    );

    return (updatedFolder: updatedFolder, unpackedItem: unpacked);
  }

  /// Calculates the total number of rows required by [items].
  int calculateTotalRows(List<WorkbenchGridItem> items) {
    if (items.isEmpty) return 0;
    int maxRow = 0;
    for (final item in items) {
      final bottom = item.y + item.spanY;
      if (bottom > maxRow) {
        maxRow = bottom;
      }
    }
    return maxRow;
  }

  /// Builds a 2D occupancy matrix of size [totalRows x columns],
  /// where each cell contains the item ID occupying it, or null if empty.
  List<List<String?>> computeOccupancyMatrix(List<WorkbenchGridItem> items) {
    final rows = calculateTotalRows(items);
    final matrix = List.generate(
      rows,
      (_) => List<String?>.filled(columns, null),
    );

    for (final item in items) {
      for (int dy = 0; dy < item.spanY; dy++) {
        final r = item.y + dy;
        if (r >= rows) continue;
        for (int dx = 0; dx < item.spanX; dx++) {
          final c = item.x + dx;
          if (c < columns) {
            matrix[r][c] = item.id;
          }
        }
      }
    }

    return matrix;
  }

  bool _canFitAt(
    Map<int, Set<int>> occupied,
    int x,
    int y,
    int spanX,
    int spanY,
  ) {
    if (x < 0 || x + spanX > columns || y < 0) return false;

    for (int dy = 0; dy < spanY; dy++) {
      final r = y + dy;
      final rowOccupied = occupied[r];
      if (rowOccupied != null) {
        for (int dx = 0; dx < spanX; dx++) {
          if (rowOccupied.contains(x + dx)) {
            return false;
          }
        }
      }
    }
    return true;
  }

  void _markOccupied(
    Map<int, Set<int>> occupied,
    int x,
    int y,
    int spanX,
    int spanY,
  ) {
    for (int dy = 0; dy < spanY; dy++) {
      final r = y + dy;
      final row = occupied.putIfAbsent(r, () => <int>{});
      for (int dx = 0; dx < spanX; dx++) {
        row.add(x + dx);
      }
    }
  }
}
