import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/widgets/chat_bubble.dart';

void main() {
  group('ChatBubbleClipper geometry tests', () {
    test('Right bubble at minHeight 44 has tail tip at y = 22 and centers vertically', () {
      final style = ChatBubbleStyle.content(
        side: ChatBubbleSide.right,
        backgroundColor: Colors.blue,
      );
      final clipper = ChatBubbleClipper(style);
      const size = Size(100, 44);
      final path = clipper.getClip(size);

      // Tail width is 8, so body edge is at x = 92
      // Tail tip should be at (size.width, 22) = (100, 22)
      expect(path.contains(const Offset(99, 22)), isTrue);

      // Near top of tail at y = 14, body at x = 91 must be intact (no indentation)
      expect(path.contains(const Offset(91, 14)), isTrue);
      // Cut circle is tangent at x = 92, y = 14, so x < 92 is never cut into
      for (double y = 0; y <= 44; y += 2) {
        if (y >= 14 && y <= 30) {
          expect(path.contains(Offset(90, y)), isTrue, reason: 'Body at x=90, y=$y must not be dented');
        }
      }
    });

    test('Right bubble at height 80 (two lines) keeps tail at y = 22', () {
      final style = ChatBubbleStyle.content(
        side: ChatBubbleSide.right,
        backgroundColor: Colors.blue,
      );
      final clipper = ChatBubbleClipper(style);
      const size = Size(100, 80);
      final path = clipper.getClip(size);

      // Tail tip remains at y = 22
      expect(path.contains(const Offset(99, 22)), isTrue);

      // Tail does NOT move to center (y = 40)
      // At x = 99, y = 40 (beyond body edge 92), there is no tail tip
      expect(path.contains(const Offset(99, 40)), isFalse);

      // Body at x = 90, y = 14..30 must not be dented
      for (double y = 14; y <= 30; y += 2) {
        expect(path.contains(Offset(90, y)), isTrue, reason: 'Body at x=90, y=$y must not be dented');
      }
    });

    test('Left bubble at minHeight 44 and height 80 has tail tip at (0, 22) and no body dent', () {
      final style = ChatBubbleStyle.content(
        side: ChatBubbleSide.left,
        backgroundColor: Colors.blue,
      );
      final clipper = ChatBubbleClipper(style);

      // Single line height 44
      const size44 = Size(100, 44);
      final path44 = clipper.getClip(size44);
      expect(path44.contains(const Offset(1, 22)), isTrue);
      // Body edge is at x = 8, so x = 9, 10 must be fully intact
      expect(path44.contains(const Offset(9, 14)), isTrue);
      expect(path44.contains(const Offset(9, 22)), isTrue);

      // Two lines height 80
      const size80 = Size(100, 80);
      final path80 = clipper.getClip(size80);
      expect(path80.contains(const Offset(1, 22)), isTrue);
      expect(path80.contains(const Offset(1, 40)), isFalse);
      expect(path80.contains(const Offset(9, 14)), isTrue);
    });
  });
}
