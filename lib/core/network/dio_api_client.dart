import 'dart:async';

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
    FutureOr<void> Function()? onSessionInvalidated,
  }) : _dio = dio,
       _tokenStorage = tokenStorage,
       _tokenRefresher = tokenRefresher,
       _deviceContext = deviceContext,
       _onSessionInvalidated = onSessionInvalidated;

  final Dio _dio;
  final TokenStorage _tokenStorage;
  final TokenRefresher _tokenRefresher;
  final ClientDeviceContext _deviceContext;
  final FutureOr<void> Function()? _onSessionInvalidated;
  final Map<Object, CancelToken> _cancelTokens = <Object, CancelToken>{};
  Future<void>? _refreshInFlight;
  Future<void>? _sessionInvalidationInFlight;

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
  Future<List<int>> getBytes(
    String path, {
    Object? cancelTag,
    void Function(int received, int total)? onProgress,
  }) => _request<List<int>>(
    path: path,
    method: 'GET',
    responseType: ResponseType.bytes,
    cancelTag: cancelTag,
    onReceiveProgress: onProgress,
  );

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

  @override
  Future<T> postMultipart<T>(
    String path, {
    Map<String, Object?>? query,
    required MultipartUploadFile file,
    String fieldName = 'file',
    bool retryOnUnauthorized = true,
  }) => _request<T>(
    path: path,
    method: 'POST',
    query: query,
    dataFactory:
        () => FormData.fromMap(<String, Object>{
          fieldName: MultipartFile.fromStream(
            file.openRead,
            file.length,
            filename: file.name,
          ),
        }),
    retryOnUnauthorized: retryOnUnauthorized,
  );

  Future<T> _request<T>({
    required String path,
    required String method,
    Map<String, Object?>? query,
    Object? data,
    Object? Function()? dataFactory,
    Map<String, String>? headers,
    bool hasRetriedAfterRefresh = false,
    bool retryOnUnauthorized = true,
    ResponseType? responseType,
    Object? cancelTag,
    void Function(int received, int total)? onReceiveProgress,
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
        data: dataFactory?.call() ?? data,
        queryParameters: query,
        options: Options(
          method: method,
          responseType: responseType,
          headers: <String, String>{
            ..._deviceContext.requestHeaders,
            ...?headers,
            if (headers?.containsKey('Authorization') != true &&
                accessToken != null &&
                accessToken.isNotEmpty)
              'Authorization': 'Bearer $accessToken',
          },
        ),
        cancelToken:
            cancelTag == null
                ? null
                : (_cancelTokens[cancelTag] = CancelToken()),
        onReceiveProgress: onReceiveProgress,
      );
      if (cancelTag != null) _cancelTokens.remove(cancelTag);
      return _unwrap<T>(response.data);
    } on DioException catch (error) {
      if (cancelTag != null) _cancelTokens.remove(cancelTag);
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
          await _invalidateSession();
          rethrow;
        }
        return _request<T>(
          path: path,
          method: method,
          query: query,
          data: data,
          dataFactory: dataFactory,
          headers: headers,
          hasRetriedAfterRefresh: true,
          retryOnUnauthorized: retryOnUnauthorized,
          responseType: responseType,
          cancelTag: cancelTag,
          onReceiveProgress: onReceiveProgress,
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
      await _invalidateSession();
      rethrow;
    }
  }

  Future<void> _invalidateSession() {
    final inFlight = _sessionInvalidationInFlight;
    if (inFlight != null) return inFlight;
    final invalidation = () async {
      await _tokenRefresher.clearSession();
      await _onSessionInvalidated?.call();
    }();
    _sessionInvalidationInFlight = invalidation;
    return invalidation.whenComplete(() {
      if (identical(_sessionInvalidationInFlight, invalidation)) {
        _sessionInvalidationInFlight = null;
      }
    });
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
