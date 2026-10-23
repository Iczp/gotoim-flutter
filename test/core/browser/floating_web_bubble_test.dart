import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/browser/floating_web_bubble.dart';

void main() {
  group('FloatingWebBubble', () {
    testWidgets(
      'touch preview button and long press show an in-memory thumbnail',
      (tester) async {
        var restored = 0;
        final bytes = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 184,
                  height: 52,
                  child: FloatingWebBubble(
                    url: 'https://example.test',
                    thumbnail: bytes,
                    onRestore: () => restored++,
                    onClose: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(
          find.byKey(const ValueKey('floating_web_thumbnail_button')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('floating_web_thumbnail_preview')),
          findsOneWidget,
        );
        expect(restored, 0);
        await tester.tap(
          find.byKey(const ValueKey('floating_web_thumbnail_button')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('floating_web_thumbnail_preview')),
          findsNothing,
        );
        await tester.longPress(find.text('example.test').first);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('floating_web_thumbnail_preview')),
          findsOneWidget,
        );
        expect(restored, 0);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'renders title, domain and handles onRestore and onClose taps',
      (tester) async {
        var restored = false;
        var closed = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: FloatingWebBubble(
                  url: 'https://im.gotoim.com/news/article-1',
                  title: '快讯头条',
                  onRestore: () => restored = true,
                  onClose: () => closed = true,
                ),
              ),
            ),
          ),
        );

        // Verify title and domain
        expect(find.text('快讯头条'), findsOneWidget);
        expect(find.text('im.gotoim.com'), findsOneWidget);

        // Tap body -> triggers restore
        await tester.tap(find.text('快讯头条'));
        await tester.pump();
        expect(restored, isTrue);

        // Tap close (X) -> triggers close
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pump();
        expect(closed, isTrue);
      },
    );
  });
}
