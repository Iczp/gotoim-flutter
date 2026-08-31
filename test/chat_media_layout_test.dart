import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/features/chat/presentation/message_content/media_message_layout.dart';

void main() {
  const constraints = BoxConstraints(maxWidth: 240);

  test('media message layout preserves a landscape ratio within limits', () {
    expect(
      MediaMessageLayout.sizeFor(
        constraints: constraints,
        aspectRatio: 16 / 9,
        fallbackAspectRatio: 1,
      ),
      const Size(240, 135),
    );
  });

  test('media message layout preserves a portrait ratio within limits', () {
    expect(
      MediaMessageLayout.sizeFor(
        constraints: constraints,
        aspectRatio: 0.5,
        fallbackAspectRatio: 1,
      ),
      const Size(90, 180),
    );
  });
}
