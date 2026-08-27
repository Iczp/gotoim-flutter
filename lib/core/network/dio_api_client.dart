import 'package:dio/dio.dart';

import 'api_client.dart';
import 'api_exception.dart';
import 'token_refresher.dart';
import 'token_storage.dart';
import 'jwt_token_expiry.dart';
import '../device/client_device_context.dart';

/// The single authenticated HTTP transport for repositories.
class DioApiClient implements ApiClient {
  DioApiClient({
    required Dio dio,
    required TokenStorage tokenStorage,
    required TokenRefresher tokenRefresher,
    required ClientDeviceContext deviceContext,
  }) : _dio = dio,
       _tokenStorage = tokenStorage,
       _tokenRefresher = tokenRefresher,
       _deviceContext = deviceContext;

  final Dio _dio;
  final TokenStorage _tokenStorage;
  final TokenRefresher _tokenRefresher;
  final ClientDeviceContext _deviceContext;
  final Map<Object, CancelToken> _cancelTokens = <Object, CancelToken>{};
  Future<void>? _refreshInFlight;

  @override
  Future<void> cancelByTag(Object tag) async {
    _cancelTokens.remove(tag)?.cancel('Cancelled by request tag');
  }

  @override
  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    bool retryOnUnauthorized = true,
  }) {
    return _request<T>(
      path: path,
      method: 'GET',
      query: query,
      retryOnUnauthorized: retryOnUnauthorized,
    );
  }

  @override
  Future<T> post<T>(
    String path, {
    Map<String, Object?>? query,
    Object? data,
    Map<String, String>? headers,
    bool retryOnUnauthorized = true,
  }) {
    return _request<T>(
      path: path,
      method: 'POST',
      query: query,
      data: data,
      headers: headers,
      retryOnUnauthorized: retryOnUnauthorized,
    );
  }

  Future<T> _request<T>({
    required String path,
    required String method,
    Map<String, Object?>? query,
    Object? data,
    Map<String, String>? headers,
    bool hasRetriedAfterRefresh = false,
    bool retryOnUnauthorized = true,
  }) async {
    final usesStoredAccessToken = headers?.containsKey('Authorization') != true;
    var accessToken = await _tokenStorage.readAccessToken();
    if (retryOnUnauthorized &&
        usesStoredAccessToken &&
        !hasRetriedAfterRefresh &&
        accessToken != null &&
        accessToken.isNotEmpty &&
        shouldRefreshJwt(accessToken)) {
      await _refreshOrClear();
      accessToken = await _tokenStorage.readAccessToken();
    }
    try {
      final response = await _dio.request<dynamic>(
        path,
        data: data,
        queryParameters: query,
        options: Options(
          method: method,
          headers: <String, String>{
            ..._deviceContext.requestHeaders,
            ...?headers,
            if (headers?.containsKey('Authorization') != true &&
                accessToken != null &&
                accessToken.isNotEmpty)
              'Authorization': 'Bearer $accessToken',
          },
        ),
      );
      return _unwrap<T>(response.data);
    } on DioException catch (error) {
      if (retryOnUnauthorized &&
          usesStoredAccessToken &&
          error.response?.statusCode == 401 &&
          !hasRetriedAfterRefresh) {
        try {
          final currentToken = await _tokenStorage.readAccessToken();
          if (currentToken == accessToken) {
            await _refreshOnce();
          }
        } catch (_) {
          await _tokenRefresher.clearSession();
          rethrow;
        }
        return _request<T>(
          path: path,
          method: method,
          query: query,
          data: data,
          headers: headers,
          hasRetriedAfterRefresh: true,
          retryOnUnauthorized: retryOnUnauthorized,
        );
      }
      throw _toApiException(error);
    }
  }

  Future<void> _refreshOnce() {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;
    final refresh = _tokenRefresher.refreshAccessToken();
    _refreshInFlight = refresh;
    return refresh.whenComplete(() {
      if (identical(_refreshInFlight, refresh)) _refreshInFlight = null;
    });
  }

  Future<void> _refreshOrClear() async {
    try {
      await _refreshOnce();
    } catch (_) {
      await _tokenRefresher.clearSession();
      rethrow;
    }
  }

  T _unwrap<T>(dynamic data) {
    if (data is Map && (data['success'] == false || data['error'] is Map)) {
      final error = data['error'];
      final message =
          error is Map
              ? (error['message'] ?? 'Request failed').toString()
              : 'Request failed';
      throw ApiException(
        message,
        code: error is Map ? error['code']?.toString() : null,
      );
    }
    final value =
        data is Map<String, dynamic> && data.containsKey('result')
            ? data['result']
            : data;
    return value as T;
  }

  ApiException _toApiException(DioException error) {
    final data = error.response?.data;
    final responseError = data is Map ? data['error'] : null;
    final message =
        responseError is Map && responseError['message'] != null
            ? responseError['message'].toString()
            : data is Map && data['error_description'] != null
            ? data['error_description'].toString()
            : error.message ?? 'Network request failed';
    return ApiException(
      message,
      statusCode: error.response?.statusCode,
      code: responseError is Map ? responseError['code']?.toString() : null,
    );
  }
}
