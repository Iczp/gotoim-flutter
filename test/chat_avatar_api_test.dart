import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';
import 'package:gotoim_flutter/features/user/data/chat_avatar_api.dart';

void main() {
  test(
    'avatar upload keeps Swagger path, file field and progress contract',
    () async {
      final client = _AvatarApiClient();
      final api = ChatAvatarApi(client);
      var progress = 0;

      final owner = await api.uploadPortrait(
        chatObjectId: 42,
        file: MultipartUploadFile(
          name: 'avatar.jpg',
          length: 3,
          openRead: () => Stream<List<int>>.value(<int>[1, 2, 3]),
        ),
        onProgress: (sent, total) => progress = sent * total,
      );

      expect(client.path, '/api/chat/chat-object/42/upload-portrait');
      expect(client.fieldName, 'file');
      expect(client.file?.name, 'avatar.jpg');
      expect(progress, 9);
      expect(owner.id, 42);
      expect(owner.imageUrl, '/avatars/42.jpg');
    },
  );
}

class _AvatarApiClient implements ApiClient {
  String? path;
  String? fieldName;
  MultipartUploadFile? file;

  @override
  Future<T> postMultipart<T>(
    String requestPath, {
    Map<String, Object?>? query,
    Map<String, Object?>? extraFields,
    required MultipartUploadFile file,
    String fieldName = 'file',
    void Function(int sent, int total)? onProgress,
    bool retryOnUnauthorized = true,
  }) async {

    path = requestPath;
    this.fieldName = fieldName;
    this.file = file;
    onProgress?.call(file.length, file.length);
    return <String, dynamic>{
          'id': 42,
          'displayName': '测试用户',
          'thumbnail': '/avatars/42.jpg',
          'objectTypeDescription': 'User',
        }
        as T;
  }

  @override
  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    bool retryOnUnauthorized = true,
  }) => throw UnimplementedError();

  @override
  Future<T> post<T>(
    String path, {
    Map<String, Object?>? query,
    Object? data,
    Map<String, String>? headers,
    bool retryOnUnauthorized = true,
  }) => throw UnimplementedError();

  @override
  Future<void> cancelByTag(Object tag) async {}

  @override
  Future<List<int>> getBytes(
    String path, {
    Object? cancelTag,
    void Function(int received, int total)? onProgress,
  }) async => const <int>[];
}
