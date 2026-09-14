import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:gotoim_flutter/core/config/app_environment.dart';
import 'package:gotoim_flutter/core/media/app_image_cache_manager.dart';
import 'package:gotoim_flutter/core/media/media_preview.dart';
import 'package:gotoim_flutter/core/widgets/app_avatar.dart';
import 'package:gotoim_flutter/features/chat/data/models/chat_message.dart';
import 'package:gotoim_flutter/features/chat/presentation/message_content/image_message_content.dart';

import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _MockPathProvider extends PathProviderPlatform {
  _MockPathProvider(this.tempPath);
  final String tempPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => tempPath;

  @override
  Future<String?> getApplicationSupportPath() async => tempPath;

  @override
  Future<String?> getTemporaryPath() async => tempPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() {
    dotenv.loadFromString(envString: 'APP_NAME=Test');
    tempDir = Directory.systemTemp.createTempSync('img_offline_test');
    PathProviderPlatform.instance = _MockPathProvider(tempDir.path);
  });

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('AppImageCacheManager Tests', () {
    test('AppImageCacheManager instance is initialized and stats return valid map', () async {
      final manager = AppImageCacheManager.instance;
      expect(manager, isNotNull);

      final stats = await AppImageCacheManager.getStats();
      expect(stats, isNotNull);
      expect(stats.containsKey('directory') || stats.containsKey('platform'), isTrue);
    });

    test('getCachedPath returns null when URL has not been cached', () async {
      final cached = await AppImageCacheManager.getCachedPath('https://example.com/non_existent.png');
      expect(cached, isNull);
    });
  });

  group('ImageMessageContent offline & local file priority tests', () {
    testWidgets('renders Image.memory when bytes are present', (tester) async {
      final message = ChatMessage(
        localId: 'msg-bytes-1',
        serverId: 1,
        clientMessageId: 'msg-bytes-1',
        ownerId: 1,
        sessionUnitId: 'unit-1',
        senderSessionUnitId: 'unit-1',
        messageType: 2,
        state: 'sent',
        score: 1,
        createdAt: DateTime.now(),
        raw: const <String, dynamic>{
          'content': <String, dynamic>{
            'url': 'https://example.com/test.jpg',
            'fileName': 'test.jpg',
          },
        },
      );

      // 1x1 transparent PNG bytes
      final dummyBytes = Uint8List.fromList(<int>[
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
        0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
        0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
        0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImageMessageContent(
              message: message,
              bytes: dummyBytes,
              apiBaseUrl: '',
              progress: null,
              mediaItems: const [],
              initialIndex: 0,
            ),
          ),
        ),
      );

      // Verify that Image.memory is rendered, and CachedNetworkImage is NOT rendered
      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    testWidgets('renders Image.file when local file exists on disk', (tester) async {
      // Create a temporary local file
      final tempDir = Directory.systemTemp.createTempSync('image_offline_test');
      final tempFile = File('${tempDir.path}${Platform.pathSeparator}test_offline.jpg')
        ..writeAsBytesSync(<int>[1, 2, 3]);

      try {
        final message = ChatMessage(
          localId: 'msg-local-1',
          serverId: 2,
          clientMessageId: 'msg-local-1',
          ownerId: 1,
          sessionUnitId: 'unit-1',
          senderSessionUnitId: 'unit-1',
          messageType: 2,
          state: 'sent',
          score: 2,
          createdAt: DateTime.now(),
          raw: <String, dynamic>{
            'content': <String, dynamic>{
              'url': 'https://example.com/test_remote.jpg',
              'path': tempFile.path,
              'fileName': 'test_offline.jpg',
            },
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ImageMessageContent(
                message: message,
                bytes: null,
                apiBaseUrl: '',
                progress: null,
                mediaItems: const [],
                initialIndex: 0,
              ),
            ),
          ),
        );

        // When local file exists, it should use Image.file directly without CachedNetworkImage
        expect(find.byType(Image), findsOneWidget);
        expect(find.byType(CachedNetworkImage), findsNothing);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    testWidgets('uses CachedNetworkImage with AppImageCacheManager when no local file exists', (tester) async {
      final message = ChatMessage(
        localId: 'msg-remote-1',
        serverId: 3,
        clientMessageId: 'msg-remote-1',
        ownerId: 1,
        sessionUnitId: 'unit-1',
        senderSessionUnitId: 'unit-1',
        messageType: 2,
        state: 'sent',
        score: 3,
        createdAt: DateTime.now(),
        raw: const <String, dynamic>{
          'content': <String, dynamic>{
            'url': 'https://example.com/remote_image.jpg',
            'fileName': 'remote_image.jpg',
          },
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImageMessageContent(
              message: message,
              bytes: null,
              apiBaseUrl: 'https://example.com',
              progress: null,
              mediaItems: const [],
              initialIndex: 0,
            ),
          ),
        ),
      );

      // Verify CachedNetworkImage is used and its cacheManager is AppImageCacheManager.instance
      final cachedImageFinder = find.byType(CachedNetworkImage);
      expect(cachedImageFinder, findsOneWidget);
      final widget = tester.widget<CachedNetworkImage>(cachedImageFinder);
      expect(widget.cacheManager, equals(AppImageCacheManager.instance));
    });
  });

  group('AppAvatar placeholder & fallback tests', () {
    testWidgets('AppAvatar does not render CircularProgressIndicator in placeholder', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appEnvironmentProvider.overrideWithValue(
              AppEnvironment.fromDotEnv(AppFlavor.development),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: AppAvatar(
                name: '张三',
                imageUrl: 'https://example.com/avatar.jpg',
                size: 48,
              ),
            ),
          ),
        ),
      );

      // Verify there is NO CircularProgressIndicator (no stuck loading circle)
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Verify the fallback initials '张' is displayed cleanly
      expect(find.text('张'), findsOneWidget);
    });
  });

  group('DefaultMediaDownloader & AppImageCacheManager integration', () {
    test('getCachedPath inspects AppImageCacheManager', () async {
      final downloader = DefaultMediaDownloader.instance;
      const item = MediaPreviewItem(
        id: 'downloader-test-1',
        messageId: 'msg-1',
        type: MediaPreviewType.image,
        source: 'https://example.com/not_cached.jpg',
        heroTag: 'hero-1',
      );

      final cached = await downloader.getCachedPath(item);
      expect(cached, isNull);
    });
  });
}
