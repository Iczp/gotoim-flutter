import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';
import 'package:gotoim_flutter/features/call_center/data/datasources/call_center_api.dart';
import 'package:gotoim_flutter/features/call_center/data/repositories/call_center_repository.dart';

void main() {
  test(
    'transfer targets use the Swagger shop-waiter contract and page result',
    () async {
      final client = _CallCenterApiClient();
      final repository = CallCenterRepository(CallCenterApi(client));

      final page = await repository.loadTransferTargets(
        shopKeeperId: 18,
        keyword: '客服',
        skipCount: 30,
      );

      expect(client.getPath, '/api/chat/shop-waiter');
      expect(client.getQuery, <String, Object?>{
        'ShopKeeperId': 18,
        'IsContainsShopKeeper': true,
        'Keyword': '客服',
        'SkipCount': 30,
        'MaxResultCount': 30,
      });
      expect(page.items.single.name, '小李客服');
      expect(page.items.single.roleLabel, '客服');
      expect(page.hasMore, isTrue);
    },
  );

  test('transfer submits the current session and selected target', () async {
    final client = _CallCenterApiClient();
    final repository = CallCenterRepository(CallCenterApi(client));

    await repository.transferTo(
      sessionUnitId: 'b943c10e-78e5-4d50-bb7a-a9b92e25d4f5',
      destinationId: 99,
    );

    expect(client.postPath, '/api/chat/call-center/transfer-to');
    expect(client.postQuery, <String, Object?>{
      'sessionUnitId': 'b943c10e-78e5-4d50-bb7a-a9b92e25d4f5',
      'destinationId': 99,
    });
  });
}

class _CallCenterApiClient implements ApiClient {
  String? getPath;
  Map<String, Object?>? getQuery;
  String? postPath;
  Map<String, Object?>? postQuery;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    bool retryOnUnauthorized = true,
  }) async {
    getPath = path;
    getQuery = query;
    return <String, dynamic>{
          'items': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 99,
              'displayName': '小李客服',
              'objectType': 8,
              'serviceStatusDescription': '服务中',
            },
          ],
          'totalCount': 32,
        }
        as T;
  }

  @override
  Future<T> post<T>(
    String path, {
    Map<String, Object?>? query,
    Object? data,
    Map<String, String>? headers,
    bool retryOnUnauthorized = true,
  }) async {
    postPath = path;
    postQuery = query;
    return <String, dynamic>{} as T;
  }

  @override
  Future<T> postMultipart<T>(
    String path, {
    Map<String, Object?>? query,
    required MultipartUploadFile file,
    String fieldName = 'file',
    void Function(int sent, int total)? onProgress,
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
