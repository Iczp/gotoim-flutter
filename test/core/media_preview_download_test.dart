import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/media/media_preview.dart';
import 'package:gotoim_flutter/core/media/video_viewer.dart';
import 'package:gotoim_flutter/features/chat/data/models/chat_message.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  @override
  Future<void> init() async {}
  @override
  Future<void> dispose(int textureId) async {}
  @override
  Future<int?> create(DataSource dataSource) async => 1;
  @override
  Future<void> setLooping(int textureId, bool looping) async {}
  @override
  Future<void> play(int textureId) async {}
  @override
  Future<void> pause(int textureId) async {}
  @override
  Future<void> setVolume(int textureId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int textureId, double speed) async {}
  @override
  Future<void> seekTo(int textureId, Duration position) async {}
  @override
  Future<Duration> getPosition(int textureId) async => Duration.zero;
  @override
  Stream<VideoEvent> videoEventsFor(int textureId) {
    return Stream.value(VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 10),
      size: const Size(1920, 1080),
    ));
  }
}

ChatMessage _createTestMsg({
  required String id,
  required int messageType,
  required int score,
  String? url,
  String? thumb,
}) {
  return ChatMessage(
    localId: id,
    serverId: int.tryParse(id),
    clientMessageId: id,
    ownerId: 1,
    sessionUnitId: 'session-1',
    senderSessionUnitId: 'sender-1',
    messageType: messageType,
    state: 'received',
    score: score,
    createdAt: DateTime.fromMillisecondsSinceEpoch(score * 1000),
    raw: <String, dynamic>{
      'content': <String, dynamic>{
        if (url != null) 'url': url,
        if (thumb != null) 'thumbnailUrl': thumb,
        'fileName': '$id.jpg',
      },
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  VideoPlayerPlatform.instance = _FakeVideoPlayerPlatform();

  group('Media Gallery Ordering & reverse: true handling', () {
    test('natural chronological ordering is reversed from desc messages array', () {
      // In ChatController, messages array is sorted by score DESC (newest at index 0)
      // because ListView.builder uses reverse: true.
      final messages = [
        _createTestMsg(id: '3', messageType: 2, score: 300, url: 'https://example.com/3.jpg'), // Newest
        _createTestMsg(id: '2', messageType: 2, score: 200, url: 'https://example.com/2.jpg'),
        _createTestMsg(id: '1', messageType: 2, score: 100, url: 'https://example.com/1.jpg'), // Oldest
      ];

      // Building gallery items with messages.reversed:
      final gallery = messages.reversed
          .where((m) => m.messageType == 2 || m.messageType == 4)
          .map(
            (m) => MediaPreviewItem(
              id: m.localId,
              messageId: m.localId,
              type: MediaPreviewType.image,
              source: m.mediaUrl ?? '',
              heroTag: 'hero-${m.localId}',
            ),
          )
          .toList();

      expect(gallery.length, equals(3));
      // Oldest is at page 0
      expect(gallery[0].id, equals('1'));
      expect(gallery[1].id, equals('2'));
      // Newest is at last page
      expect(gallery[2].id, equals('3'));

      // Tapping message '2':
      final indexForMsg2 = gallery.indexWhere((it) => it.id == '2');
      expect(indexForMsg2, equals(1));

      // Tapping message '3' (latest):
      final indexForMsg3 = gallery.indexWhere((it) => it.id == '3');
      expect(indexForMsg3, equals(2));
    });
  });

  group('System Message Tag Parsing', () {
    test('correctly parses <a uid="..."> and <a oid="...">', () {
      const text = '<a uid="fdc164ec-39bf-87bb-70aa-3a0e9fa5397e">林惠娟</a> 邀请 <a uid="a1b2c3d4-0000-0000-0000-000000000000">张三</a> 加入 <a oid="5847">GotoIM群聊</a>';
      final regExp = RegExp(
        r'<a\s+uid="([^"]+)">([^<]+)</a>|<a\s+oid="([^"]+)">([^<]+)</a>',
        caseSensitive: false,
      );

      final matches = regExp.allMatches(text).toList();
      expect(matches.length, equals(3));

      // Match 1: uid 林惠娟
      expect(matches[0].group(1), equals('fdc164ec-39bf-87bb-70aa-3a0e9fa5397e'));
      expect(matches[0].group(2), equals('林惠娟'));

      // Match 2: uid 张三
      expect(matches[1].group(1), equals('a1b2c3d4-0000-0000-0000-000000000000'));
      expect(matches[1].group(2), equals('张三'));

      // Match 3: oid GotoIM群聊
      expect(matches[2].group(3), equals('5847'));
      expect(matches[2].group(4), equals('GotoIM群聊'));
    });
  });

  group('Media Preview Item CopyWith', () {
    test('copies with updated localPath and source', () {
      const item = MediaPreviewItem(
        id: 'img1',
        messageId: 'msg1',
        type: MediaPreviewType.image,
        source: 'https://example.com/orig.jpg',
        thumbnail: 'https://example.com/thumb.jpg',
        heroTag: 'hero-1',
      );

      final updated = item.copyWith(
        localPath: '/data/user/0/cache/attachments/img1.jpg',
      );

      expect(updated.id, equals('img1'));
      expect(updated.thumbnail, equals('https://example.com/thumb.jpg'));
      expect(updated.localPath, equals('/data/user/0/cache/attachments/img1.jpg'));
    });
  });

  group('Cached Media Preview Does Not Display 0%', () {
    testWidgets('already cached image opens directly without 0%', (tester) async {
      final item = MediaPreviewItem(
        id: 'cached-img',
        messageId: 'msg-1',
        type: MediaPreviewType.image,
        source: 'https://example.com/cached.jpg',
        localPath: 'C:/fake/path/cached.jpg',
        heroTag: 'hero-cached',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => MediaPreview.open(context, items: [item]),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pump();

      // Must NEVER display 0%
      expect(find.text('0%'), findsNothing);
    });

    testWidgets('video preview presents top-level floating window button', (tester) async {
      final tempFile = File('${Directory.systemTemp.path}/test_demo_${DateTime.now().microsecondsSinceEpoch}.mp4');
      await tempFile.writeAsBytes([1, 2, 3]);
      addTearDown(() async {
        if (await tempFile.exists()) await tempFile.delete();
      });

      final videoItem = MediaPreviewItem(
        id: 'vid-1',
        messageId: 'msg-v1',
        type: MediaPreviewType.video,
        source: 'https://example.com/demo.mp4',
        localPath: tempFile.path,
        heroTag: 'hero-vid',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => MediaPreview.open(context, items: [videoItem]),
              child: const Text('Open Video'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Video'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Top chrome must have close button and floating mini-window button
      expect(find.byTooltip('关闭'), findsOneWidget);
      expect(find.byTooltip('缩小为浮窗'), findsOneWidget);
      expect(find.byIcon(Icons.picture_in_picture_alt), findsOneWidget);
    });

    testWidgets('video viewer hides playback controls when isDragging is true', (tester) async {
      final videoItem = MediaPreviewItem(
        id: 'vid-2',
        messageId: 'msg-v2',
        type: MediaPreviewType.video,
        source: 'https://example.com/demo2.mp4',
        heroTag: 'hero-vid-2',
      );

      // Render VideoViewer with isDragging: true
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoViewer(
              item: videoItem,
              active: true,
              items: [videoItem],
              initialIndex: 0,
              isDragging: true,
            ),
          ),
        ),
      );

      // Playback controls slider and seekbar must NOT be rendered when dragging
      expect(find.byType(Slider), findsNothing);
    });
  });
}
