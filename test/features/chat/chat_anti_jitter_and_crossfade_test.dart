import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/media/image_viewer.dart';
import 'package:gotoim_flutter/features/chat/application/chat_controller.dart';
import 'package:gotoim_flutter/features/chat/data/models/chat_message.dart';
import 'package:gotoim_flutter/features/chat/presentation/widgets/chat_composer.dart';

// Valid 1x1 transparent PNG bytes
final kTransparentPng = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  group('ImageViewer Dual-Layer Cross-Fade Tests', () {
    testWidgets('ImageViewer renders single image when no thumbnail is provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImageViewer(
              source: 'assets/test.png',
              bytes: kTransparentPng,
              enableLogs: false,
            ),
          ),
        ),
      );

      expect(find.byType(ImageViewer), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('ImageViewer renders Stack with thumbnail and highRes AnimatedOpacity when thumbnailBytes provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImageViewer(
              source: 'http://example.com/highres.jpg',
              bytes: kTransparentPng,
              thumbnailBytes: kTransparentPng,
              enableLogs: false,
            ),
          ),
        ),
      );

      expect(find.byType(ImageViewer), findsOneWidget);
      expect(find.byType(Image), findsNWidgets(2));
      expect(find.byType(AnimatedOpacity), findsOneWidget);
    });

    testWidgets('ImageViewer renders Stack with thumbnail and highRes AnimatedOpacity when thumbnail URL provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImageViewer(
              source: 'http://example.com/highres.jpg',
              thumbnail: 'http://example.com/thumb.jpg',
              enableLogs: false,
            ),
          ),
        ),
      );

      expect(find.byType(ImageViewer), findsOneWidget);
      expect(find.byType(Image), findsNWidgets(2));
      expect(find.byType(AnimatedOpacity), findsOneWidget);
    });
  });

  group('ChatComposer Anti-Jitter & Keyboard Transition Tests', () {
    testWidgets('Toggling function tray opens panel smoothly and caches height', (tester) async {
      final fakeController = _FakeChatController();
      final textInput = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            resizeToAvoidBottomInset: false,
            body: ChatComposer(
              controller: fakeController,
              input: textInput,
              quoteContentBuilder: (_) => const SizedBox.shrink(),
            ),
          ),
        ),
      );

      // Initially function tray is closed
      expect(find.byTooltip('更多功能'), findsOneWidget);
      expect(find.text('相册'), findsNothing);

      // Tap + button
      await tester.tap(find.byTooltip('更多功能'));
      await tester.pumpAndSettle();

      // Function tray is now visible
      expect(find.byTooltip('打开键盘'), findsOneWidget);
      expect(find.text('相册'), findsOneWidget);
      expect(find.text('拍摄'), findsOneWidget);

      // Close input area
      final state = tester.state<ChatComposerState>(find.byType(ChatComposer));
      state.closeInputArea();
      await tester.pumpAndSettle();

      expect(find.text('相册'), findsNothing);
    });

    testWidgets('Simulated keyboard pop up sets animated container height without jitter', (tester) async {
      final fakeController = _FakeChatController();
      final textInput = TextEditingController();

      // Start with 0 bottom inset
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(viewInsets: EdgeInsets.zero),
            child: Scaffold(
              resizeToAvoidBottomInset: false,
              body: ChatComposer(
                controller: fakeController,
                input: textInput,
                quoteContentBuilder: (_) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      );

      // Open functions panel
      await tester.tap(find.byTooltip('更多功能'));
      await tester.pumpAndSettle();
      expect(find.text('相册'), findsOneWidget);

      // Tap TextField while panel is open to initiate switch to keyboard
      await tester.tap(find.byType(TextField));
      await tester.pump();

      // Now simulate keyboard popping up (e.g. height 320)
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(viewInsets: EdgeInsets.only(bottom: 320)),
            child: Scaffold(
              resizeToAvoidBottomInset: false,
              body: ChatComposer(
                controller: fakeController,
                input: textInput,
                quoteContentBuilder: (_) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Keyboard has taken over, function panel is dismissed cleanly
      expect(find.text('相册'), findsNothing);
    });
  });
}

class _FakeChatController extends ChangeNotifier implements ChatController {
  @override
  bool get isOfficialAccount => false;
  @override
  List<Map<String, dynamic>> get officialAccountMenus => const [];
  @override
  bool get isMuted => false;
  @override
  ChatMessage? get quoting => null;
  @override
  bool get isSending => false;
  @override
  bool get mentionVisible => false;
  @override
  void updateMentionInput(String value) {}
  @override
  Future<void> cancelVoiceRecording() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

