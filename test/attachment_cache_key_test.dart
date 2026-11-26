import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/config/app_environment.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';
import 'package:gotoim_flutter/core/services/file/attachment_cache.dart';
import 'package:gotoim_flutter/core/services/file/attachment_transfer_service.dart';
import 'package:gotoim_flutter/core/services/file/file_picker_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakeApiClient extends Fake implements ApiClient {
  int getBytesCalls = 0;
  final List<String> requestedUrls = [];
  Uint8List payload = Uint8List.fromList(<int>[10, 20, 30, 40]);

  @override
  Future<List<int>> getBytes(
    String path, {
    Map<String, Object?>? query,
    Object? cancelTag,
    void Function(int received, int total)? onProgress,
  }) async {
    getBytesCalls++;
    requestedUrls.add(path);
    onProgress?.call(payload.length, payload.length);
    return payload;
  }

  @override
  Future<void> cancelByTag(Object tag) async {}
}

class _FakeFilePickerService extends Fake implements FilePickerService {}

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.rootPath);

  final String rootPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => rootPath;

  @override
  Future<String?> getApplicationSupportPath() async => rootPath;
}

void main() {
  test('normalizes attachment cache keys by server origin and BlobId while stripping signed query params', () {
    const blobId = '3fa85f64-5717-4562-b3fc-2c963f66afa6';
    final urlIdentityA =
        '/api/chat/file/$blobId?su=su-a&msg=1001&exp=1700000100&sig=sig-a';
    final urlIdentityB =
        '/api/chat/file/${blobId.toUpperCase()}?su=su-b&msg=1002&rootMsg=900&exp=1700000900&sig=sig-b';
    final queryStyleUrl =
        'https://chat.example.com/file?id=$blobId&exp=1700000500&sig=sig-c';

    final keyA = normalizeAttachmentCacheKey(
      source: urlIdentityA,
      fallbackKey: 'local-msg-1',
      serverOrigin: 'https://chat.example.com',
    );
    final keyB = normalizeAttachmentCacheKey(
      source: urlIdentityB,
      fallbackKey: 'local-msg-2',
      serverOrigin: 'https://chat.example.com',
    );
    final keyQuery = normalizeAttachmentCacheKey(
      source: queryStyleUrl,
      fallbackKey: 'local-msg-3',
      serverOrigin: 'https://chat.example.com',
    );
    final keyOtherOrigin = normalizeAttachmentCacheKey(
      source: urlIdentityA,
      fallbackKey: 'local-msg-1',
      serverOrigin: 'https://staging.example.com',
    );

    expect(extractAttachmentBlobId(urlIdentityA), blobId);
    expect(extractAttachmentBlobId(queryStyleUrl), blobId);
    expect(keyA, keyB);
    expect(keyA, keyQuery);
    expect(keyA, isNot(keyOtherOrigin));
  });

  test('AttachmentTransferService reuses downloaded BlobId cache across signed URLs and isolates per account on disk', () async {
    final tempDir = await Directory.systemTemp.createTemp('gotoim-attach-cache-');
    final previousPlatform = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    addTearDown(() async {
      PathProviderPlatform.instance = previousPlatform;
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    dotenv.loadFromString(envString: 'API_BASE_URL=https://chat.example.com');
    final client = _FakeApiClient();
    final cache = createAttachmentCache(
      storagePathResolver: () async => tempDir.path,
    );
    final service = AttachmentTransferService(
      client: client,
      environment: AppEnvironment.fromDotEnv(AppFlavor.development),
      filePickerService: _FakeFilePickerService(),
      cache: cache,
    );

    const blobId = 'e6550997-d94d-cdc6-0153-3a25003274d7';
    final urlA = '/api/chat/file/$blobId?su=su-a&msg=501&exp=100&sig=aaa';
    final urlB = '/api/chat/file/$blobId?su=su-b&msg=501&exp=200&sig=bbb';

    await service.download(
      id: 'local-msg-a',
      source: urlA,
      fileName: 'doc.pdf',
      userId: 'account-1',
      chatTarget: 'su-a',
      messageDate: DateTime(2026, 11, 26),
    );
    expect(client.getBytesCalls, 1);

    // Second identity of the same account views same BlobId with different signed URL: hits disk cache, 0 network calls.
    await service.download(
      id: 'local-msg-b',
      source: urlB,
      fileName: 'doc.pdf',
      userId: 'account-1',
      chatTarget: 'su-b',
      messageDate: DateTime(2026, 11, 26),
    );
    expect(client.getBytesCalls, 1);
    expect(service.stateFor('local-msg-b').isReady, isTrue);
    expect(service.stateFor('local-msg-b').localPath, isNotNull);

    // Switching to another account must NOT reuse account-1's private cache file.
    final otherAccountPath = await service.findCachedPath(
      id: 'local-msg-other-account',
      source: urlA,
      fileName: 'doc.pdf',
      userId: 'account-2',
      chatTarget: 'su-c',
      messageDate: DateTime(2026, 11, 26),
    );
    expect(otherAccountPath, isNull);
  });
}
