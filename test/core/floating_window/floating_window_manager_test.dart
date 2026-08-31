import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/floating_window/floating_window.dart';

void main() {
  group('FloatingWindowManager', () {
    test('show updates an existing id and brings it to front', () {
      final manager = FloatingWindowManager();
      manager.show(id: 'a', child: const SizedBox());
      final firstZ = manager.find('a')!.zIndex;
      manager.show(id: 'b', child: const SizedBox());
      manager.show(id: 'a', child: const SizedBox(width: 10));

      expect(manager.entries, hasLength(2));
      expect(manager.find('a')!.zIndex, greaterThan(firstZ));
      expect(manager.entries.last.id, 'a');
    });

    test('hide, showWindow, close and closeAll manage visibility', () {
      final manager = FloatingWindowManager();
      manager.show(id: 'a', child: const SizedBox());
      manager.hide('a');
      expect(manager.find('a')!.visible, isFalse);
      manager.showWindow('a');
      expect(manager.find('a')!.visible, isTrue);
      manager.close('a');
      expect(manager.contains('a'), isFalse);
      manager.show(id: 'b', child: const SizedBox());
      manager.closeAll();
      expect(manager.entries, isEmpty);
    });
  });

  group('FloatingWindowBounds', () {
    const bounds = FloatingWindowBounds(Rect.fromLTWH(10, 20, 300, 400));

    test('clamps a position inside the available rectangle', () {
      expect(
        bounds.clampPosition(const Offset(999, 999), const Size(100, 80)),
        const Offset(210, 340),
      );
    });

    test('limits a size to the available rectangle', () {
      final size = bounds.clampSize(
        const Size(900, 700),
        const FloatingWindowOptions(minSize: Size(120, 72)),
      );
      expect(size, const Size(300, 400));
    });
  });
}
