import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';
import 'package:gotoim_flutter/features/group/data/room_api.dart';

void main() {
  test('RoomApi.createRoom constructs proper payload for face-to-face group', () async {
    final client = _MockApiClient();
    final api = RoomApi(client);

    await api.createRoom(
      name: '面对面群 1234',
      ownerId: 99,
      code: '1234',
      type: 0,
      description: '面对面建群',
      chatObjectIdList: const <int>[],
    );

    expect(client.lastPostPath, '/api/chat/room');
    expect(client.lastPostData, isA<Map<String, dynamic>>());
    final data = client.lastPostData as Map<String, dynamic>;
    expect(data['name'], '面对面群 1234');
    expect(data['code'], '1234');
    expect(data['ownerId'], 99);
    expect(data['type'], 0);
    expect(data['description'], '面对面建群');
    expect(data['chatObjectIdList'], isEmpty);
  });

  test('RoomApi.createRoom constructs proper payload for friend-selected group', () async {
    final client = _MockApiClient();
    final api = RoomApi(client);

    await api.createRoom(
      name: '群(张三、李四)',
      ownerId: 88,
      code: '',
      type: 0,
      description: '群(张三、李四)',
      chatObjectIdList: [101, 102],
    );

    expect(client.lastPostPath, '/api/chat/room');
    final data = client.lastPostData as Map<String, dynamic>;
    expect(data['name'], '群(张三、李四)');
    expect(data['code'], '');
    expect(data['ownerId'], 88);
    expect(data['chatObjectIdList'], [101, 102]);
  });
}

class _MockApiClient implements ApiClient {
  String? lastPostPath;
  Object? lastPostData;
  Map<String, Object?>? lastPostQuery;

  @override
  Future<T> post<T>(
    String path, {
    Map<String, Object?>? query,
    Object? data,
    Map<String, String>? headers,
    bool retryOnUnauthorized = true,
  }) async {
    lastPostPath = path;
    lastPostData = data;
    lastPostQuery = query;
    return <String, dynamic>{'id': 1001, 'name': 'Created Room'} as T;
  }

  @override
  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    bool retryOnUnauthorized = true,
  }) async {
    throw UnimplementedError();
  }

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
    throw UnimplementedError();
  }

  @override
  Future<void> cancelByTag(Object tag) async {}

  @override
  Future<List<int>> getBytes(
    String path, {
    Object? cancelTag,
    void Function(int received, int total)? onProgress,
  }) async {
    throw UnimplementedError();
  }
}
