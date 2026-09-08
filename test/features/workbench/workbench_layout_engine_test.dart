import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/features/workbench/domain/workbench_grid_item.dart';
import 'package:gotoim_flutter/features/workbench/domain/workbench_layout_engine.dart';

void main() {
  const engine = WorkbenchLayoutEngine();

  group('WorkbenchLayoutEngine - Bin-Packing', () {
    test('packs four 1x1 items into a single row (row 0, col 0..3)', () {
      final items = [
        const WorkbenchGridItem(id: '1', title: 'App 1', type: WorkbenchGridItemType.app, x: 0, y: 0),
        const WorkbenchGridItem(id: '2', title: 'App 2', type: WorkbenchGridItemType.app, x: 0, y: 0),
        const WorkbenchGridItem(id: '3', title: 'App 3', type: WorkbenchGridItemType.app, x: 0, y: 0),
        const WorkbenchGridItem(id: '4', title: 'App 4', type: WorkbenchGridItemType.app, x: 0, y: 0),
      ];

      final packed = engine.packItems(items);

      expect(packed.length, 4);
      expect(packed[0].x, 0);
      expect(packed[0].y, 0);
      expect(packed[1].x, 1);
      expect(packed[1].y, 0);
      expect(packed[2].x, 2);
      expect(packed[2].y, 0);
      expect(packed[3].x, 3);
      expect(packed[3].y, 0);
      expect(engine.calculateTotalRows(packed), 1);
    });

    test('packs 4x1 banner spanning all 4 columns', () {
      final items = [
        const WorkbenchGridItem(id: 'banner1', title: 'Banner', type: WorkbenchGridItemType.banner, x: 0, y: 0, spanX: 4, spanY: 1),
        const WorkbenchGridItem(id: 'app1', title: 'App 1', type: WorkbenchGridItemType.app, x: 0, y: 0),
      ];

      final packed = engine.packItems(items);

      expect(packed[0].x, 0);
      expect(packed[0].y, 0);
      expect(packed[0].spanX, 4);
      expect(packed[0].spanY, 1);

      // app1 must be pushed to next row
      expect(packed[1].x, 0);
      expect(packed[1].y, 1);
      expect(engine.calculateTotalRows(packed), 2);
    });

    test('packs mixed 2x2 card with 1x1 items filling remaining spaces', () {
      final items = [
        const WorkbenchGridItem(id: 'card', title: 'Card 2x2', type: WorkbenchGridItemType.cardWidget, x: 0, y: 0, spanX: 2, spanY: 2),
        const WorkbenchGridItem(id: 'a1', title: 'A1', type: WorkbenchGridItemType.app, x: 0, y: 0),
        const WorkbenchGridItem(id: 'a2', title: 'A2', type: WorkbenchGridItemType.app, x: 0, y: 0),
        const WorkbenchGridItem(id: 'a3', title: 'A3', type: WorkbenchGridItemType.app, x: 0, y: 0),
        const WorkbenchGridItem(id: 'a4', title: 'A4', type: WorkbenchGridItemType.app, x: 0, y: 0),
      ];

      final packed = engine.packItems(items);

      // Card is at (0, 0, 2, 2)
      expect(packed[0].x, 0);
      expect(packed[0].y, 0);

      // a1 should fill (2, 0)
      expect(packed[1].x, 2);
      expect(packed[1].y, 0);

      // a2 should fill (3, 0)
      expect(packed[2].x, 3);
      expect(packed[2].y, 0);

      // a3 should fill (2, 1) beside the card
      expect(packed[3].x, 2);
      expect(packed[3].y, 1);

      // a4 should fill (3, 1) beside the card
      expect(packed[4].x, 3);
      expect(packed[4].y, 1);

      expect(engine.calculateTotalRows(packed), 2);
    });
  });

  group('WorkbenchLayoutEngine - Collision & Displacement', () {
    test('displaces item when dragging over occupied cell', () {
      final items = [
        const WorkbenchGridItem(id: '1', title: 'A1', type: WorkbenchGridItemType.app, x: 0, y: 0),
        const WorkbenchGridItem(id: '2', title: 'A2', type: WorkbenchGridItemType.app, x: 1, y: 0),
        const WorkbenchGridItem(id: '3', title: 'A3', type: WorkbenchGridItemType.app, x: 2, y: 0),
      ];

      // Drag A3 over position of A1 (0, 0)
      final displaced = engine.previewDisplacement(
        items: items,
        dragItem: items[2],
        targetX: 0,
        targetY: 0,
      );

      // A3 is excluded from displaced list (rendered separately as drag ghost)
      expect(displaced.length, 2);

      // All displaced items must not overlap with ghost at (0, 0)
      final ghostRect = const GridRect(x: 0, y: 0, spanX: 1, spanY: 1);
      for (final item in displaced) {
        expect(item.rect.intersects(ghostRect), isFalse);
      }
    });
  });

  group('WorkbenchLayoutEngine - Folder Merge & Unpack', () {
    test('can merge two apps into a folder', () {
      const app1 = WorkbenchGridItem(id: 'a1', title: 'App 1', type: WorkbenchGridItemType.app, x: 0, y: 0);
      const app2 = WorkbenchGridItem(id: 'a2', title: 'App 2', type: WorkbenchGridItemType.app, x: 1, y: 0);

      expect(engine.canMergeIntoFolder(app1, app2), isTrue);

      final folder = engine.mergeIntoFolder(
        baseItem: app1,
        droppedItem: app2,
        folderTitle: '工具箱',
      );

      expect(folder.type, WorkbenchGridItemType.folder);
      expect(folder.title, '工具箱');
      expect(folder.children?.length, 2);
      expect(folder.children?[0].id, 'a1');
      expect(folder.children?[1].id, 'a2');
    });

    test('unpacks child from folder', () {
      const app1 = WorkbenchGridItem(id: 'a1', title: 'App 1', type: WorkbenchGridItemType.app, x: 0, y: 0);
      const app2 = WorkbenchGridItem(id: 'a2', title: 'App 2', type: WorkbenchGridItemType.app, x: 1, y: 0);
      final folder = engine.mergeIntoFolder(baseItem: app1, droppedItem: app2);

      final result = engine.unpackItemFromFolder(folder: folder, childId: 'a2');

      expect(result.unpackedItem.id, 'a2');
      expect(result.updatedFolder?.children?.length, 1);
      expect(result.updatedFolder?.children?[0].id, 'a1');
    });
  });

  group('WorkbenchLayoutEngine - Occupancy Matrix', () {
    test('computes occupancy matrix accurately', () {
      final items = [
        const WorkbenchGridItem(id: 'b', title: 'Banner', type: WorkbenchGridItemType.banner, x: 0, y: 0, spanX: 4, spanY: 1),
        const WorkbenchGridItem(id: 'c', title: 'Card', type: WorkbenchGridItemType.cardWidget, x: 0, y: 1, spanX: 2, spanY: 2),
      ];

      final matrix = engine.computeOccupancyMatrix(items);

      expect(matrix.length, 3); // 1 for banner, 2 for card
      expect(matrix[0], ['b', 'b', 'b', 'b']);
      expect(matrix[1], ['c', 'c', null, null]);
      expect(matrix[2], ['c', 'c', null, null]);
    });
  });

  group('WorkbenchLayoutEngine - Reorder & Pack', () {
    test('reorders item forward accurately', () {
      final items = [
        const WorkbenchGridItem(id: '1', title: 'A1', type: WorkbenchGridItemType.app, x: 0, y: 0),
        const WorkbenchGridItem(id: '2', title: 'A2', type: WorkbenchGridItemType.app, x: 1, y: 0),
        const WorkbenchGridItem(id: '3', title: 'A3', type: WorkbenchGridItemType.app, x: 2, y: 0),
        const WorkbenchGridItem(id: '4', title: 'A4', type: WorkbenchGridItemType.app, x: 3, y: 0),
      ];

      // Drag A1 to A3 (col 2, row 0)
      final reordered = engine.reorderAndPack(
        items: items,
        dragId: '1',
        targetX: 2,
        targetY: 0,
      );

      expect(reordered[0].id, '2');
      expect(reordered[0].x, 0);

      expect(reordered[1].id, '3');
      expect(reordered[1].x, 1);

      expect(reordered[2].id, '1');
      expect(reordered[2].x, 2);

      expect(reordered[3].id, '4');
      expect(reordered[3].x, 3);
    });

    test('reorders item backward accurately', () {
      final items = [
        const WorkbenchGridItem(id: '1', title: 'A1', type: WorkbenchGridItemType.app, x: 0, y: 0),
        const WorkbenchGridItem(id: '2', title: 'A2', type: WorkbenchGridItemType.app, x: 1, y: 0),
        const WorkbenchGridItem(id: '3', title: 'A3', type: WorkbenchGridItemType.app, x: 2, y: 0),
        const WorkbenchGridItem(id: '4', title: 'A4', type: WorkbenchGridItemType.app, x: 3, y: 0),
      ];

      // Drag A4 to A1 (col 0, row 0)
      final reordered = engine.reorderAndPack(
        items: items,
        dragId: '4',
        targetX: 0,
        targetY: 0,
      );

      expect(reordered[0].id, '4');
      expect(reordered[0].x, 0);

      expect(reordered[1].id, '1');
      expect(reordered[1].x, 1);

      expect(reordered[2].id, '2');
      expect(reordered[2].x, 2);

      expect(reordered[3].id, '3');
      expect(reordered[3].x, 3);
    });
  });
}
