import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/config/app_environment.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';
import 'package:gotoim_flutter/core/services/file/attachment_cache.dart';
import 'package:gotoim_flutter/core/services/file/attachment_transfer_service.dart';
import 'package:gotoim_flutter/core/services/file/file_picker_service.dart';
import 'package:gotoim_flutter/core/utils/api_url_resolver.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakeApiClient extends Fake implements ApiClient {
  int getBytesCalls = 0;
  int signCalls = 0;
  bool allowSign = true;
  final List<String> requestedUrls = [];
  final List<Map<String, Object?>?> signQueries = [];
  final List<Object> cancelledTags = [];
  Completer<void>? startedCompleter;
  Completer<List<int>>? pendingCompleter;
  Uint8List payload = Uint8List.fromList(<int>[10, 20, 30, 40]);

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
    requestedUrls.add(path);
    if (startedCompleter != null && !startedCompleter!.isCompleted) {
      startedCompleter!.complete();
    }
    if (pendingCompleter != null) {
      return pendingCompleter!.future;
    }
    onProgress?.call(payload.length, payload.length);
    return payload;
  }

  @override
  Future<void> cancelByTag(Object tag) async {
    cancelledTags.add(tag);
  }
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

    // Switching to another account with the SAME local message id must NOT reuse account-1's in-memory or disk cache.
    final otherAccountPath = await service.findCachedPath(
      id: 'local-msg-a',
      source: urlA,
      fileName: 'doc.pdf',
      userId: 'account-2',
      chatTarget: 'su-c',
      messageDate: DateTime(2026, 11, 26),
    );
    expect(otherAccountPath, isNull);
    expect(service.stateFor('local-msg-a', userId: 'account-2').isReady, isFalse);

    service.clearSessionCache();
    expect(service.stateFor('local-msg-a', userId: 'account-1').isReady, isFalse);
  });

  test('cancel matches scoped download cancelTag both with explicit userId and active session user', () async {
    final tempDir = await Directory.systemTemp.createTemp('gotoim-attach-cancel-');
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
    final service = AttachmentTransferService(
      client: client,
      environment: AppEnvironment.fromDotEnv(AppFlavor.development),
      filePickerService: _FakeFilePickerService(),
      cache: createAttachmentCache(storagePathResolver: () async => tempDir.path),
    );

    final started = Completer<void>();
    final completer = Completer<List<int>>();
    client.startedCompleter = started;
    client.pendingCompleter = completer;

    final downloadFuture = service.download(
      id: 'local-cancel-1',
      source: '/api/chat/file/3fa85f64-5717-4562-b3fc-2c963f66afa6',
      fileName: 'big.bin',
      userId: 'account-1',
    );
    await started.future;
    expect(service.stateFor('local-cancel-1', userId: 'account-1').isDownloading, isTrue);

    await service.cancel('local-cancel-1', userId: 'account-1');
    expect(client.cancelledTags, contains('attachment-account-1::local-cancel-1'));
    expect(
      service.stateFor('local-cancel-1', userId: 'account-1').status,
      AttachmentTransferStatus.cancelled,
    );

    // Also verify omitting userId cancels using _activeUserId fallback cleanly.
    await service.cancel('local-cancel-2');
    expect(client.cancelledTags, contains('attachment-account-1::local-cancel-2'));

    completer.complete(Uint8List.fromList(<int>[1, 2, 3]));
    await downloadFuture;
    expect(
      service.stateFor('local-cancel-1', userId: 'account-1').status,
      AttachmentTransferStatus.cancelled,
    );
  });

  test('resolveAttachmentUrl appends su/msg/rootMsg and findCachedPath enforces online /sign verdict & invalidation', () async {
    final tempDir = await Directory.systemTemp.createTemp('gotoim-attach-auth-');
    final previousPlatform = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    addTearDown(() async {
      PathProviderPlatform.instance = previousPlatform;
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    const blobId = '7fa85f64-5717-4562-b3fc-2c963f66afa7';
    final resolved = resolveAttachmentUrl(
      '/api/chat/file/$blobId',
      'https://chat.example.com',
      sessionUnitId: 'su-hist-2',
      messageId: 777,
      rootMessageId: 900,
    );
    final uri = Uri.parse(resolved);
    expect(uri.queryParameters['su'], 'su-hist-2');
    expect(uri.queryParameters['msg'], '777');
    expect(uri.queryParameters['rootMsg'], '900');

    dotenv.loadFromString(envString: 'API_BASE_URL=https://chat.example.com');
    final client = _FakeApiClient();
    final cache = createAttachmentCache(storagePathResolver: () async => tempDir.path);
    final service = AttachmentTransferService(
      client: client,
      environment: AppEnvironment.fromDotEnv(AppFlavor.development),
      filePickerService: _FakeFilePickerService(),
      cache: cache,
    );

    const ctx = AttachmentAccessContext(
      sessionUnitId: 'su-hist-2',
      messageId: 777,
      rootMessageId: 900,
    );

    // Pre-populate cache via authorized download
    await service.download(
      id: 'hist-child-1',
      source: '/api/chat/file/$blobId',
      fileName: 'hist.pdf',
      userId: 'account-1',
      chatTarget: 'su-hist-2',
      messageDate: DateTime(2026, 11, 27),
      accessContext: ctx,
      verifyOnline: true,
    );
    expect(client.signCalls, 1);
    expect(client.getBytesCalls, 1);

    // Cached hit uses cached 60s verdict without redundant /sign call
    final hitPath = await service.findCachedPath(
      id: 'hist-child-1',
      source: '/api/chat/file/$blobId',
      fileName: 'hist.pdf',
      userId: 'account-1',
      chatTarget: 'su-hist-2',
      messageDate: DateTime(2026, 11, 27),
      accessContext: ctx,
      verifyOnline: true,
    );
    expect(hitPath, isNotNull);
    expect(client.signCalls, 1);

    // After recall/deletion invalidation, next check must re-verify online; denied -> blocks cached hit
    client.allowSign = false;
    service.invalidateMessageAccess(messageId: 777, userId: 'account-1');
    final blockedPath = await service.findCachedPath(
      id: 'hist-child-1',
      source: '/api/chat/file/$blobId',
      fileName: 'hist.pdf',
      userId: 'account-1',
      chatTarget: 'su-hist-2',
      messageDate: DateTime(2026, 11, 27),
      accessContext: ctx,
      verifyOnline: true,
    );
    expect(blockedPath, isNull);
    expect(client.signCalls, 2);
  });
}
