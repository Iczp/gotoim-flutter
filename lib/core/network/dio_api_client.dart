import 'package:dio/dio.dart';

import 'api_client.dart';
import 'api_exception.dart';
import 'token_refresher.dart';
import 'token_storage.dart';
import '../device/client_device_context.dart';

/// The single authenticated HTTP transport for repositories.
class DioApiClient implements ApiClient {
  DioApiClient({
    required Dio dio,
    required TokenStorage tokenStorage,
    required TokenRefresher tokenRefresher,
    required ClientDeviceContext deviceContext,
  })  : _dio = dio,
        _tokenStorage = tokenStorage,
        _tokenRefresher = tokenRefresher,
        _deviceContext = deviceContext;

  final Dio _dio;
  final TokenStorage _tokenStorage;
  final TokenRefresher _tokenRefresher;
  final ClientDeviceContext _deviceContext;
  final Map<Object, CancelToken> _cancelTokens = <Object, CancelToken>{};

  @override
  Future<void> cancelByTag(Object tag) async {
    _cancelTokens.remove(tag)?.cancel('Cancelled by request tag');
  }

  @override
  Future<T> get<T>(String path, {Map<String, Object?>? query}) {
    return _request<T>(
      path: path,
      method: 'GET',
      query: query,
    );
  }

  @override
  Future<T> post<T>(
    String path, {
    Map<String, Object?>? query,
    Object? data,
  }) {
    return _request<T>(path: path, method: 'POST', query: query, data: data);
  }

  Future<T> _request<T>({
    required String path,
    required String method,
    Map<String, Object?>? query,
    Object? data,
    bool hasRetriedAfterRefresh = false,
  }) async {
    try {
      final accessToken = await _tokenStorage.readAccessToken();
      final response = await _dio.request<dynamic>(
        path,
        data: data,
        queryParameters: query,
        options: Options(
          method: method,
          headers: <String, String>{
            ..._deviceContext.requestHeaders,
            if (accessToken != null && accessToken.isNotEmpty)
              'Authorization': 'Bearer $accessToken',
          },
        ),
      );
      return _unwrap<T>(response.data);
    } on DioException catch (error) {
      if (error.response?.statusCode == 401 && !hasRetriedAfterRefresh) {
        try {
          await _tokenRefresher.refreshAccessToken();
        } catch (_) {
          await _tokenRefresher.clearSession();
          rethrow;
        }
        return _request<T>(
          path: path,
          method: method,
          query: query,
          data: data,
          hasRetriedAfterRefresh: true,
        );
      }
      throw _toApiException(error);
    }
  }

  T _unwrap<T>(dynamic data) {
    if (data is Map<String, dynamic> && data['success'] == false) {
      final error = data['error'];
      final message = error is Map<String, dynamic>
          ? (error['message'] ?? 'Request failed').toString()
          : 'Request failed';
      throw ApiException(message,
          code: error is Map ? error['code']?.toString() : null);
    }
    final value = data is Map<String, dynamic> && data.containsKey('result')
        ? data['result']
        : data;
    return value as T;
  }

  ApiException _toApiException(DioException error) {
    final data = error.response?.data;
    final message = data is Map && data['error_description'] != null
        ? data['error_description'].toString()
        : error.message ?? 'Network request failed';
    return ApiException(message, statusCode: error.response?.statusCode);
  }
}
