import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/widgets/parametric_chat_bubble.dart';
import 'package:gotoim_flutter/features/diagnostics/presentation/chat_bubble_diagnostics_page.dart';

void main() {
  test('parametric bubble config clamps values and emits JSON contract', () {
    const base = ParametricBubbleConfig();
    final config = base.copyWith(
      side: ParametricBubbleSide.right,
      anchor: ParametricBubbleAnchor.bottom,
      leadingCurveBend: -3,
      trailingCurveBend: 3,
      offset: 140,
      tailLength: 1,
      tailHeight: 90,
      inversion: -1,
      sharpness: 3,
      radius: 80,
    );

    expect(config.offset, 100);
    expect(config.tailLength, 4);
    expect(config.tailHeight, 48);
    expect(config.inversion, 0);
    expect(config.sharpness, 1);
    expect(config.radius, 40);
    expect(config.toJson(), <String, Object>{
      'side': 'right',
      'anchor': 'bottom',
      'leadingCurveBend': -1.0,
      'trailingCurveBend': 1.0,
      'offset': 100.0,
      'tailLength': 4.0,
      'tailHeight': 48.0,
      'inversion': 0.0,
      'sharpness': 1.0,
      'radius': 40.0,
    });
  });

  testWidgets('bubble tuner lays out and scrolls its parameter panel', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: ChatBubbleDiagnosticsPage()),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(const Size(320, 100));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(const Size(320, 56));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
