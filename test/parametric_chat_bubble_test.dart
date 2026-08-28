import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/widgets/parametric_chat_bubble.dart';

void main() {
  test('parametric bubble config clamps values and emits JSON contract', () {
    const base = ParametricBubbleConfig();
    final config = base.copyWith(
      side: ParametricBubbleSide.right,
      anchor: ParametricBubbleAnchor.bottom,
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
      'offset': 100.0,
      'tailLength': 4.0,
      'tailHeight': 48.0,
      'inversion': 0.0,
      'sharpness': 1.0,
      'radius': 40.0,
    });
  });
}
