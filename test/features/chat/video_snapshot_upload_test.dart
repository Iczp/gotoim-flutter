import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';
import 'package:gotoim_flutter/core/services/file/file_picker_service.dart';
import 'package:gotoim_flutter/features/chat/data/datasources/message_api.dart';
import 'package:gotoim_flutter/features/chat/data/datasources/message_dao.dart';
import 'package:gotoim_flutter/features/chat/data/models/chat_message.dart';
import 'package:gotoim_flutter/features/chat/data/repositories/message_repository.dart';

class _RecordingApiClient implements ApiClient {
  final List<String> multipartPaths = <String>[];
  final List<Map<String, Object?>> multipartExtraFields = <Map<String, Object?>>[];
  final List<String> postPaths = <String>[];
  final List<Object?> postBodies = <Object?>[];

  Map<String, dynamic> uploadResponse = <String, dynamic>{
    'blobId': '11111111-1111-1111-1111-111111111111',
    'url': '/api/chat/file/11111111-1111-1111-1111-111111111111',
    'snapshotBlobId': '22222222-2222-2222-2222-222222222222',
    'snapshotUrl': '/api/chat/file/22222222-2222-2222-2222-222222222222',
    'snapshotThumbnailBlobId': '33333333-3333-3333-3333-333333333333',
    'snapshotThumbnailUrl': '/api/chat/file/33333333-3333-3333-3333-333333333333',
    'fileName': 'clip.mp4',
    'contentType': 'video/mp4',
    'suffix': '.mp4',
    'size': 2048,
    'width': 1280,
    'height': 720,
    'duration': 5000,
  };

  Map<String, dynamic> sendResponse = <String, dynamic>{
    'id': 9001,
    'messageType': 4,
    'content': <String, dynamic>{
      'blobId': '11111111-1111-1111-1111-111111111111',
      'url': '/api/chat/file/11111111-1111-1111-1111-111111111111',
      'snapshotUrl': '/api/chat/file/22222222-2222-2222-2222-222222222222',
      'snapshotThumbnailUrl': '/api/chat/file/33333333-3333-3333-3333-333333333333',
    },
  };

  @override
  Future<T> put<T>(
    String path, {
    Object? data,
    Map<String, Object?>? query,
    Map<String, String>? headers,
    bool retryOnUnauthorized = true,
  }) async => <String, dynamic>{} as T;

  @override
  Future<T> postMultipart<T>(
    String path, {
    Map<String, Object?>? query,
    Map<String, Object?>? extraFields,
    required MultipartUploadFile file,
    String fieldName = 'file',
    void Function(int sent, int total)? onProgress,
    bool retryOnUnauthorized = true,
  }) async {
    multipartPaths.add(path);
    multipartExtraFields.add(extraFields ?? const <String, Object?>{});
    return uploadResponse as T;
  }

  @override
  Future<T> post<T>(
    String path, {
    Map<String, Object?>? query,
    Object? data,
    Map<String, String>? headers,
    bool retryOnUnauthorized = true,
  }) async {
    postPaths.add(path);
    postBodies.add(data);
    return sendResponse as T;
  }

  @override
  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    bool retryOnUnauthorized = true,
  }) => throw UnimplementedError();

  @override
  Future<T> delete<T>(String path, {Map<String, Object?>? query}) =>
      throw UnimplementedError();

  @override
  Future<void> cancelByTag(Object tag) async {}

  @override
  Future<List<int>> getBytes(
    String path, {
    Object? cancelTag,
    void Function(int received, int total)? onProgress,
  }) => throw UnimplementedError();
}

class _InMemoryMessageDao implements MessageDao {
  final List<ChatMessage> upserted = <ChatMessage>[];

  @override
  Future<int> maxScore(int ownerId, String sessionUnitId) async => 0;

  @override
  Future<void> upsertAll(List<ChatMessage> items) async {
    upserted.addAll(items);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('sendLocalVideo uploads snapshotFile alongside video and forwards snapshot URLs to send-video', () async {
    final apiClient = _RecordingApiClient();
    final api = MessageApi(apiClient);
    final dao = _InMemoryMessageDao();
    final repo = MessageRepository(api: api, dao: dao);

    final local = ChatMessage(
      localId: 'local-1',
      serverId: null,
      clientMessageId: 'local-1',
      ownerId: 1001,
      sessionUnitId: 'su-1',
      senderSessionUnitId: 'su-1',
      messageType: 4,
      state: 'sending',
      score: 1,
      createdAt: DateTime.now(),
      raw: const <String, dynamic>{'messageType': 4, 'content': <String, dynamic>{}},
    );

    final videoFile = await SelectedFile.fromBytes(
      Uint8List.fromList(<int>[0, 0, 0, 1]),
      name: 'clip.mp4',
      mimeType: 'video/mp4',
    );
    final thumbBytes = Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE0]);

    final sent = await repo.sendLocalVideo(
      local: local,
      file: videoFile,
      extraFields: const <String, Object?>{
        'width': 1280,
        'height': 720,
        'durationMs': 5000,
      },
      extraFiles: <String, MultipartUploadFile>{
        'snapshotFile': MultipartUploadFile(
          name: 'clip.mp4.jpg',
          length: thumbBytes.length,
          openRead: () => Stream<List<int>>.value(thumbBytes),
          contentType: 'image/jpeg',
        ),
      },
    );

    expect(apiClient.multipartPaths, <String>['/api/chat/attachments/upload-video/su-1']);
    expect(apiClient.multipartExtraFields.single['snapshotFile'], isA<MultipartUploadFile>());
    expect(apiClient.multipartExtraFields.single['durationMs'], 5000);

    expect(apiClient.postPaths, <String>['/api/chat/message-sender/send-video/su-1']);
    final sentBody = apiClient.postBodies.single as Map<String, Object?>;
    final sentContent = sentBody['content'] as Map<String, dynamic>;
    expect(sentContent['snapshotBlobId'], '22222222-2222-2222-2222-222222222222');
    expect(sentContent['snapshotThumbnailBlobId'], '33333333-3333-3333-3333-333333333333');
    expect(sentContent['duration'], 5.0);
    expect(sentContent.containsKey('durationMs'), isFalse);
    expect(sentContent.containsKey('snapshotFile'), isFalse);
    expect(sent.state, 'sent');
    expect(sent.serverId, 9001);
  });

  test('createLocalVideo persists pre-extracted dimensions, duration, and localThumbnailPath', () async {
    final apiClient = _RecordingApiClient();
    final api = MessageApi(apiClient);
    final dao = _InMemoryMessageDao();
    final repo = MessageRepository(api: api, dao: dao);

    final videoFile = await SelectedFile.fromBytes(
      Uint8List.fromList(<int>[0, 0, 0, 1]),
      name: 'clip.mp4',
      mimeType: 'video/mp4',
    );

    final local = await repo.createLocalVideo(
      ownerId: 1001,
      sessionUnitId: 'su-1',
      file: videoFile,
      width: 1920,
      height: 1080,
      durationMs: 12500,
      localThumbnailPath: 'C:/tmp/thumb.jpg',
    );

    expect(local.content['size'], 4);
    expect(local.content['width'], 1920);
    expect(local.content['height'], 1080);
    expect(local.content['duration'], 12.5);
    expect(local.content['durationMs'], 12500);
    expect(local.localThumbnailPath, 'C:/tmp/thumb.jpg');
    expect(dao.upserted, hasLength(1));
  });
}
