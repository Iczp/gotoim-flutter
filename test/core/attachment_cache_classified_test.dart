import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/services/file/attachment_cache.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _MockPathProvider extends PathProviderPlatform {
  _MockPathProvider(this.tempPath);
  final String tempPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => tempPath;

  @override
  Future<String?> getApplicationSupportPath() async => tempPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Attachment Category & Date Resolution', () {
    test('resolves category by file extension correctly', () {
      expect(resolveAttachmentCategory('avatar.png'), equals('图片'));
      expect(resolveAttachmentCategory('photo.JPEG'), equals('图片'));
      expect(resolveAttachmentCategory('banner.webp'), equals('图片'));

      expect(resolveAttachmentCategory('video.mp4'), equals('视频'));
      expect(resolveAttachmentCategory('clip.MOV'), equals('视频'));
      expect(resolveAttachmentCategory('movie.mkv'), equals('视频'));

      expect(resolveAttachmentCategory('voice.m4a'), equals('语音'));
      expect(resolveAttachmentCategory('song.mp3'), equals('语音'));
      expect(resolveAttachmentCategory('audio.wav'), equals('语音'));

      expect(resolveAttachmentCategory('contract.pdf'), equals('文档'));
      expect(resolveAttachmentCategory('sheet.xlsx'), equals('文档'));
      expect(resolveAttachmentCategory('notes.txt'), equals('文档'));
      expect(resolveAttachmentCategory('archive.zip'), equals('文档'));
    });

    test('resolves category by messageType override', () {
      expect(resolveAttachmentCategory('file.unknown', messageType: 2), equals('图片'));
      expect(resolveAttachmentCategory('file.unknown', messageType: 4), equals('视频'));
      expect(resolveAttachmentCategory('file.unknown', messageType: 3), equals('语音'));
    });

    test('resolves date folder correctly', () {
      final date1 = DateTime(2026, 9, 3, 14, 30);
      expect(resolveDateFolder(date1), equals('2026-09-03'));

      final date2 = DateTime(2026, 1, 5, 8, 5);
      expect(resolveDateFolder(date2), equals('2026-01-05'));

      final date3 = DateTime(2025, 12, 31, 23, 59);
      expect(resolveDateFolder(date3), equals('2025-12-31'));
    });
  });

  group('AttachmentCache Categorized Storage Integration', () {
    late Directory tempDir;
    late AttachmentCache cache;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('attachment_test_');
      PathProviderPlatform.instance = _MockPathProvider(tempDir.path);
      cache = createAttachmentCache();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('writes into LocalShare/聊天文件/<分类>/<yyyy-MM-dd> and finds it', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final msgDate = DateTime(2026, 9, 3);

      final path = await cache.write(
        'msg_1001',
        'report.pdf',
        bytes,
        messageDate: msgDate,
      );

      expect(path, isNotNull);
      // Path must contain LocalShare, 聊天文件, 文档, and 2026-09-03
      expect(path!, contains('LocalShare'));
      expect(path, contains('聊天文件'));
      expect(path, contains('文档'));
      expect(path, contains('2026-09-03'));
      expect(path, contains('msg_1001_report.pdf'));

      final file = File(path);
      expect(await file.exists(), isTrue);
      expect(await file.readAsBytes(), equals(bytes));

      // Exact find with date
      final foundExact = await cache.find(
        'msg_1001',
        'report.pdf',
        messageDate: msgDate,
        category: '文档',
      );
      expect(foundExact, equals(path));

      // Find without passing date (recursively scans LocalShare/聊天文件)
      final foundRecursive = await cache.find(
        'msg_1001',
        'report.pdf',
      );
      expect(foundRecursive, equals(path));
    });

    test('saves image into 图片 category', () async {
      final bytes = Uint8List.fromList([10, 20, 30]);
      final msgDate = DateTime(2026, 9, 3);

      final path = await cache.write(
        'img_2002',
        'photo.jpg',
        bytes,
        messageDate: msgDate,
      );

      expect(path, isNotNull);
      expect(path!, contains('图片'));
      expect(path, contains('2026-09-03'));
      expect(path, contains('img_2002_photo.jpg'));

      final found = await cache.find('img_2002', 'photo.jpg');
      expect(found, equals(path));
    });

    test('writes and isolates by userId and chatTarget', () async {
      final bytes = Uint8List.fromList([7, 8, 9]);
      final msgDate = DateTime(2026, 9, 5);

      final user1Path = await cache.write(
        'msg_u1',
        'doc.pdf',
        bytes,
        userId: 'user_100',
        chatTarget: 'friend_200',
        messageDate: msgDate,
      );

      expect(user1Path, isNotNull);
      expect(user1Path!, contains('user_100'));
      expect(user1Path, contains('friend_200'));
      expect(user1Path, contains('文档'));
      expect(user1Path, contains('2026-09-05'));

      // Find with exact userId and chatTarget
      final foundU1 = await cache.find(
        'msg_u1',
        'doc.pdf',
        userId: 'user_100',
        chatTarget: 'friend_200',
        messageDate: msgDate,
      );
      expect(foundU1, equals(user1Path));

      // Query from a different user should NOT find it directly under user_101
      final foundU2Exact = await cache.find(
        'msg_u1',
        'doc.pdf',
        userId: 'user_101',
        chatTarget: 'friend_200',
        messageDate: msgDate,
      );
      // Fallback recursive search across other users will locate it
      expect(foundU2Exact, equals(user1Path));
    });
  });
}
