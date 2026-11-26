import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';
import 'package:gotoim_flutter/core/services/file/attachment_reuse_registry.dart';
import 'package:gotoim_flutter/features/chat/data/datasources/message_api.dart';

class _FakeReuseApiClient extends Fake implements ApiClient {
  int postMultipartCalls = 0;
  int postCalls = 0;
  final List<String> postPaths = <String>[];
  final List<Object?> postBodies = <Object?>[];
  bool failNextPost = false;
  String issuedToken = 'tok-initial-1';
  String nextReuseToken = 'tok-reused-2';

  @override
  Future<T> postMultipart<T>(
    String path, {
    required MultipartUploadFile file,
    String fieldName = 'file',
    Map<String, Object?>? extraFields,
    Map<String, Object?>? query,
    void Function(int sent, int total)? onProgress,
    bool retryOnUnauthorized = true,
  }) async {
    postMultipartCalls++;
    onProgress?.call(file.length, file.length);
    return <String, dynamic>{
      'blobId': '11111111-1111-1111-1111-111111111111',
      'url': '/api/chat/file/11111111-1111-1111-1111-111111111111',
      'fileName': file.name,
      'reuseToken': issuedToken,
      'expireTime': DateTime.now().toUtc().add(const Duration(hours: 2)).toIso8601String(),
    } as T;
  }

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, Object?>? query,
    Map<String, String>? headers,
    bool retryOnUnauthorized = true,
  }) async {
    postCalls++;
    postPaths.add(path);
    postBodies.add(data);
    if (failNextPost) {
      failNextPost = false;
      throw StateError('reuse rejected');
    }
    return <String, dynamic>{
      'blobId': '22222222-2222-2222-2222-222222222222',
      'url': '/api/chat/file/22222222-2222-2222-2222-222222222222',
      'fileName': (data as Map<String, Object?>?)?['fileName'] ?? 'file.bin',
      'reuseToken': nextReuseToken,
      'expireTime': DateTime.now().toUtc().add(const Duration(hours: 2)).toIso8601String(),
    } as T;
  }
}

void main() {
  test('uploadAttachment caches reuseToken and redeems via /api/chat/attachments/reuse under same accountScope', () async {
    final client = _FakeReuseApiClient();
    final registry = AttachmentReuseRegistry();
    final api = MessageApi(client, reuseRegistry: registry);
    final payload = Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7]);

    final first = await api.uploadAttachment(
      sessionUnitId: 'unit-a',
      fileName: 'doc.pdf',
      fileLength: payload.length,
      openRead: () => Stream<List<int>>.value(payload),
      messageType: 5,
      accountScope: 'user-1',
      clientUploadId: 'op-1',
    );
    expect(first['blobId'], '11111111-1111-1111-1111-111111111111');
    expect(client.postMultipartCalls, 1);
    expect(client.postCalls, 0);

    var reportedProgress = 0;
    final second = await api.uploadAttachment(
      sessionUnitId: 'unit-b',
      fileName: 'doc-copy.pdf',
      fileLength: payload.length,
      openRead: () => Stream<List<int>>.value(payload),
      messageType: 5,
      accountScope: 'user-1',
      clientUploadId: 'op-2',
      onProgress: (sent, total) => reportedProgress = sent,
    );
    expect(second['blobId'], '22222222-2222-2222-2222-222222222222');
    expect(client.postMultipartCalls, 1);
    expect(client.postCalls, 1);
    expect(client.postPaths.single, '/api/chat/attachments/reuse/unit-b');
    expect(reportedProgress, payload.length);
    final body = Map<String, Object?>.from(client.postBodies.single! as Map);
    expect(body['reuseToken'], 'tok-initial-1');
    expect(body['clientUploadId'], 'op-2');
    expect(body['fileName'], 'doc-copy.pdf');
  });

  test('uploadAttachment isolates reuseToken across accounts and falls back on reuse error', () async {
    final client = _FakeReuseApiClient();
    final registry = AttachmentReuseRegistry();
    final api = MessageApi(client, reuseRegistry: registry);
    final payload = Uint8List.fromList(<int>[9, 8, 7, 6]);

    await api.uploadAttachment(
      sessionUnitId: 'unit-a',
      fileName: 'pic.png',
      fileLength: payload.length,
      openRead: () => Stream<List<int>>.value(payload),
      messageType: 2,
      accountScope: 'user-1',
      clientUploadId: 'op-1',
    );
    expect(client.postMultipartCalls, 1);

    // Different accountScope must upload directly without redeeming user-1 token
    await api.uploadAttachment(
      sessionUnitId: 'unit-c',
      fileName: 'pic.png',
      fileLength: payload.length,
      openRead: () => Stream<List<int>>.value(payload),
      messageType: 2,
      accountScope: 'user-2',
      clientUploadId: 'op-3',
    );
    expect(client.postMultipartCalls, 2);
    expect(client.postCalls, 0);

    // Reuse error for user-1 must invalidate cached entry and fall back cleanly to postMultipart
    client.failNextPost = true;
    final fallback = await api.uploadAttachment(
      sessionUnitId: 'unit-d',
      fileName: 'pic.png',
      fileLength: payload.length,
      openRead: () => Stream<List<int>>.value(payload),
      messageType: 2,
      accountScope: 'user-1',
      clientUploadId: 'op-4',
    );
    expect(fallback['blobId'], '11111111-1111-1111-1111-111111111111');
    expect(client.postCalls, 1);
    expect(client.postMultipartCalls, 3);
  });
}
