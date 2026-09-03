import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/features/chat/data/models/chat_message.dart';
import 'package:gotoim_flutter/features/chat/presentation/message_content/media_message_layout.dart';
import 'package:gotoim_flutter/features/chat/presentation/message_content/video_message_content.dart';

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

  test('ChatMessage parses videoDuration correctly', () {
    final msgInSeconds = ChatMessage(
      localId: '1',
      serverId: 1,
      clientMessageId: '1',
      ownerId: 1,
      sessionUnitId: 's1',
      senderSessionUnitId: 'u1',
      messageType: 4,
      state: 'received',
      score: 1,
      createdAt: DateTime(2026),
      raw: const <String, dynamic>{
        'content': <String, dynamic>{
          'duration': 15,
          'size': 1572864, // 1.5 MB
          'fileName': 'travel.mp4',
        },
      },
    );
    expect(msgInSeconds.videoDuration, equals(const Duration(seconds: 15)));
    expect(msgInSeconds.fileSize, equals(1572864));

    final msgInMs = ChatMessage(
      localId: '2',
      serverId: 2,
      clientMessageId: '2',
      ownerId: 1,
      sessionUnitId: 's1',
      senderSessionUnitId: 'u1',
      messageType: 4,
      state: 'received',
      score: 2,
      createdAt: DateTime(2026),
      raw: const <String, dynamic>{
        'content': <String, dynamic>{
          'durationMs': 75000, // 1 min 15 sec
        },
      },
    );
    expect(msgInMs.videoDuration, equals(const Duration(milliseconds: 75000)));
  });

  testWidgets('VideoMessageContent renders duration and file size without file name', (
    tester,
  ) async {
    final message = ChatMessage(
      localId: 'v1',
      serverId: 1,
      clientMessageId: 'v1',
      ownerId: 1,
      sessionUnitId: 's1',
      senderSessionUnitId: 'u1',
      messageType: 4,
      state: 'received',
      score: 1,
      createdAt: DateTime(2026),
      raw: const <String, dynamic>{
        'content': <String, dynamic>{
          'url': 'https://example.com/demo.mp4',
          'fileName': 'demo_secret_name.mp4',
          'duration': 15,
          'size': 1024 * 1024 * 2, // 2.0 MB
        },
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: VideoMessageContent(
              message: message,
              apiBaseUrl: 'https://example.com',
              progress: null,
              mediaItems: const [],
              initialIndex: 0,
            ),
          ),
        ),
      ),
    );

    // Duration 00:15 must be displayed
    expect(find.text('00:15'), findsOneWidget);
    // File size 2.0 MB must be displayed
    expect(find.text('2.0 MB'), findsOneWidget);
    // File name must NOT be displayed
    expect(find.text('demo_secret_name.mp4'), findsNothing);
  });
}
