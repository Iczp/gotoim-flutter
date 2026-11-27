import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/config/app_environment.dart';
import 'package:gotoim_flutter/core/media/media_preview.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';
import 'package:gotoim_flutter/core/services/file/attachment_cache.dart';
import 'package:gotoim_flutter/core/services/file/attachment_transfer_service.dart';
import 'package:gotoim_flutter/core/services/file/file_picker_service.dart';
import 'package:gotoim_flutter/features/chat/application/chat_controller.dart';
import 'package:gotoim_flutter/features/chat/data/models/chat_message.dart';
import 'package:gotoim_flutter/features/chat/presentation/message_content/history_message_content.dart';
import 'package:gotoim_flutter/features/chat/presentation/message_content/image_message_content.dart';
import 'package:gotoim_flutter/features/chat/presentation/message_content/video_message_content.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakeApiClient extends Fake implements ApiClient {
  int signCalls = 0;
  int getBytesCalls = 0;
  bool allowSign = true;
  final List<Map<String, Object?>?> signQueries = [];
  Uint8List payload = Uint8List.fromList(<int>[1, 2, 3, 4]);

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, Object?>? query,
    Map<String, String>? headers,
    bool retryOnUnauthorized = true,
  }) async {
    signCalls++;
    signQueries.add(query);
    if (!allowSign) {
      throw StateError('403 Forbidden');
    }
    return <String, dynamic>{'url': '/signed'} as T;
  }

  @override
  Future<List<int>> getBytes(
    String path, {
    Map<String, Object?>? query,
    Object? cancelTag,
    void Function(int received, int total)? onProgress,
  }) async {
    getBytesCalls++;
    onProgress?.call(payload.length, payload.length);
    return payload;
  }
}

class _FakeFilePickerService extends Fake implements FilePickerService {
  int saveCalls = 0;

  @override
  Future<SavedFile?> saveFile(FileSaveRequest request) async {
    saveCalls++;
    return SavedFile(uri: Uri.file('/tmp/${request.fileName}'));
  }
}

class _MemoryAttachmentCache implements AttachmentCache {
  final Map<String, Uint8List> _files = {};

  @override
  Future<String?> write(
    String key,
    String fileName,
    Uint8List bytes, {
    String? userId,
    String? chatTarget,
    DateTime? messageDate,
    String? category,
  }) async {
    final path = '/mem/$userId/$key/$fileName';
    _files[path] = bytes;
    return path;
  }

  @override
  Future<String?> find(
    String key,
    String fileName, {
    String? userId,
    String? chatTarget,
    DateTime? messageDate,
    String? category,
  }) async => null;

  @override
  Future<bool> exists(String path) async => _files.containsKey(path);

  @override
  Future<Uint8List?> readBytes(String path) async => _files[path];

  @override
  Future<void> open(String path) async {}
}

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.rootPath);

  final String rootPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => rootPath;

  @override
  Future<String?> getApplicationSupportPath() async => rootPath;
}

void main() {
  test(
    'open and saveAs force online verification even within short verdict cache window',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('gotoim-force-verify-');
      final prevPlatform = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
      addTearDown(() async {
        PathProviderPlatform.instance = prevPlatform;
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      dotenv.loadFromString(envString: 'API_BASE_URL=https://chat.example.com');
      final client = _FakeApiClient();
      final picker = _FakeFilePickerService();
      final service = AttachmentTransferService(
        client: client,
        environment: AppEnvironment.fromDotEnv(AppFlavor.development),
        filePickerService: picker,
        cache: createAttachmentCache(storagePathResolver: () async => tempDir.path),
      );
      const blobId = '4fa85f64-5717-4562-b3fc-2c963f66afa4';
      const ctx = AttachmentAccessContext(
        sessionUnitId: 'su-1',
        messageId: 501,
      );

      await service.download(
        id: 'doc-1',
        source: '/api/chat/file/$blobId',
        fileName: 'report.pdf',
        userId: '10',
        chatTarget: 'su-1',
        accessContext: ctx,
        verifyOnline: true,
      );
      expect(client.signCalls, 1);

      // Revoke access on server within the 5-second cache window.
      client.allowSign = false;

      final saved = await service.saveAs(
        id: 'doc-1',
        source: '/api/chat/file/$blobId',
        fileName: 'report.pdf',
        userId: '10',
        chatTarget: 'su-1',
        accessContext: ctx,
        verifyOnline: true,
        forceVerifyOnline: true,
      );
      expect(saved, isNull);
      expect(picker.saveCalls, 0);
      expect(client.signCalls, 2);

      await expectLater(
        () => service.open(
          id: 'doc-1',
          source: '/api/chat/file/$blobId',
          fileName: 'report.pdf',
          userId: '10',
          chatTarget: 'su-1',
          accessContext: ctx,
          verifyOnline: true,
          forceVerifyOnline: true,
        ),
        throwsA(isA<StateError>()),
      );
      expect(client.signCalls, 3);
    },
  );

  testWidgets(
    'ImageMessageContent gates cached local private image and revokes on invalidateMessageAccess',
    (tester) async {
      final tempDir = Directory.systemTemp.createTempSync('gotoim-img-gate-');
      final prevPlatform = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
      addTearDown(() {
        PathProviderPlatform.instance = prevPlatform;
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final localFile = File('${tempDir.path}/cached.png');
      // 1x1 valid transparent PNG bytes
      localFile.writeAsBytesSync(const <int>[
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
        0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
        0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
        0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
        0x42, 0x60, 0x82,
      ]);

      dotenv.loadFromString(envString: 'API_BASE_URL=https://chat.example.com');
      final client = _FakeApiClient();
      final service = AttachmentTransferService(
        client: client,
        environment: AppEnvironment.fromDotEnv(AppFlavor.development),
        filePickerService: _FakeFilePickerService(),
        cache: _MemoryAttachmentCache(),
      );

      const blobId = '5fa85f64-5717-4562-b3fc-2c963f66afa5';
      final message = ChatMessage(
        localId: 'msg-img-1',
        serverId: 888,
        clientMessageId: null,
        ownerId: 10,
        sessionUnitId: 'su-img-1',
        senderSessionUnitId: 'su-sender',
        messageType: 2,
        state: 'received',
        score: 888000000,
        createdAt: DateTime(2026, 11, 27),
        raw: <String, dynamic>{
          'localFilePath': localFile.path,
          'content': <String, dynamic>{
            'url': '/api/chat/file/$blobId',
            'width': 100,
            'height': 100,
          },
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            attachmentTransferServiceProvider.overrideWith((_) => service),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ImageMessageContent(
                message: message,
                bytes: null,
                apiBaseUrl: 'https://chat.example.com',
                progress: null,
                mediaItems: const <MediaPreviewItem>[],
                initialIndex: 0,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(client.signCalls, 1);
      expect(find.byType(Image), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsNothing);

      // Server denies access and recall/delete invalidation runs -> image must disappear.
      client.allowSign = false;
      service.invalidateMessageAccess(messageId: 888, userId: '10');
      await tester.pumpAndSettle();

      expect(client.signCalls, 2);
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    },
  );

  testWidgets(
    'VideoMessageContent fails closed on local cover when private authorization is denied',
    (tester) async {
      final tempDir = Directory.systemTemp.createTempSync('gotoim-vid-gate-');
      final prevPlatform = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
      addTearDown(() {
        PathProviderPlatform.instance = prevPlatform;
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final thumbFile = File('${tempDir.path}/thumb.png');
      thumbFile.writeAsBytesSync(const <int>[
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
        0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
        0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
        0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
        0x42, 0x60, 0x82,
      ]);

      dotenv.loadFromString(envString: 'API_BASE_URL=https://chat.example.com');
      final client = _FakeApiClient()..allowSign = false;
      final service = AttachmentTransferService(
        client: client,
        environment: AppEnvironment.fromDotEnv(AppFlavor.development),
        filePickerService: _FakeFilePickerService(),
        cache: createAttachmentCache(storagePathResolver: () async => tempDir.path),
      );

      const blobId = '6fa85f64-5717-4562-b3fc-2c963f66afa6';
      final videoMessage = ChatMessage(
        localId: 'msg-vid-1',
        serverId: 889,
        clientMessageId: null,
        ownerId: 10,
        sessionUnitId: 'su-vid-1',
        senderSessionUnitId: 'su-sender',
        messageType: 4,
        state: 'received',
        score: 889000000,
        createdAt: DateTime(2026, 11, 27),
        raw: <String, dynamic>{
          'localThumbnailPath': thumbFile.path,
          'content': <String, dynamic>{
            'url': '/api/chat/file/$blobId',
            'size': 2048,
          },
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoMessageContent(
              message: videoMessage,
              apiBaseUrl: 'https://chat.example.com',
              progress: null,
              mediaItems: const <MediaPreviewItem>[],
              initialIndex: 0,
              attachmentTransferService: service,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(client.signCalls, 1);
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.play_circle_fill), findsNothing);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    },
  );

  testWidgets(
    'HistoryMessageContent opens detail dialog and propagates viewer su, child msg, and rootMsg',
    (tester) async {
      final tempDir = Directory.systemTemp.createTempSync('gotoim-hist-detail-');
      final prevPlatform = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
      addTearDown(() {
        PathProviderPlatform.instance = prevPlatform;
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      dotenv.loadFromString(envString: 'API_BASE_URL=https://chat.example.com');
      final client = _FakeApiClient();
      final service = AttachmentTransferService(
        client: client,
        environment: AppEnvironment.fromDotEnv(AppFlavor.development),
        filePickerService: _FakeFilePickerService(),
        cache: _MemoryAttachmentCache(),
      );

      const childImgBlob = '11111111-1111-4111-8111-111111111111';
      const childFileBlob = '22222222-2222-4222-8222-222222222222';
      final historyMsg = ChatMessage(
        localId: 'msg-hist-root',
        serverId: 900,
        clientMessageId: null,
        ownerId: 10,
        sessionUnitId: 'su-viewer',
        senderSessionUnitId: 'su-sender',
        messageType: 12,
        state: 'received',
        score: 900000000,
        createdAt: DateTime(2026, 11, 27),
        raw: <String, dynamic>{
          'content': <String, dynamic>{
            'title': '项目资料合并转发',
            'description': '包含图片、文件与子转发',
            'messageList': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 701,
                'sessionUnitId': 'su-original-source',
                'messageType': 'Image',
                'senderName': 'Alice',
                'content': <String, dynamic>{
                  'url': '/api/chat/file/$childImgBlob',
                },
              },
              <String, dynamic>{
                'id': 702,
                'messageType': 5,
                'senderName': 'Bob',
                'content': <String, dynamic>{
                  'url': '/api/chat/file/$childFileBlob',
                  'fileName': 'spec.pdf',
                  'size': 1024,
                },
              },
            ],
          },
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HistoryMessageContent(
              message: historyMsg,
              apiBaseUrl: 'https://chat.example.com',
              attachmentTransferService: service,
            ),
          ),
        ),
      );

      await tester.tap(find.text('项目资料合并转发'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      // Detail dialog renders both child items and authorizes child image with su-viewer/msg=701/rootMsg=900.
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('spec.pdf'), findsOneWidget);
      expect(
        client.signQueries.any(
          (q) =>
              q?['blobId'] == childImgBlob &&
              q?['sessionUnitId'] == 'su-viewer' &&
              q?['messageId'] == 701 &&
              q?['rootMessageId'] == 900,
        ),
        isTrue,
      );

      // Tapping child file downloads using su-viewer, msg=702, rootMsg=900.
      await tester.tap(find.text('spec.pdf'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        client.signQueries.any(
          (q) =>
              q?['blobId'] == childFileBlob &&
              q?['sessionUnitId'] == 'su-viewer' &&
              q?['messageId'] == 702 &&
              q?['rootMessageId'] == 900,
        ),
        isTrue,
      );
    },
  );
}
