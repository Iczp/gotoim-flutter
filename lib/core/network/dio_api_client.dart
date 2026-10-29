import 'dart:async';

import 'package:dio/dio.dart';

import 'api_client.dart';
import 'api_exception.dart';
import 'token_refresher.dart';
import 'token_storage.dart';
import 'jwt_token_expiry.dart';
import '../device/client_device_context.dart';
import '../logging/app_logger.dart';
import '../logging/diagnostic_trace.dart';
import '../logging/log_sanitizer.dart';

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
  static Future<void>? _globalRefreshInFlight;
  static Future<void>? _globalSessionInvalidationInFlight;

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
    Map<String, Object?>? extraFields,
    required MultipartUploadFile file,
    String fieldName = 'file',
    void Function(int sent, int total)? onProgress,
    bool retryOnUnauthorized = true,
  }) {
    final mediaType = _resolveMediaType(file.contentType, file.name);
    final effectiveFilename =
        file.name.trim().isNotEmpty
            ? file.name.trim()
            : 'upload_${DateTime.now().millisecondsSinceEpoch}.${mediaType?.subtype ?? 'bin'}';
    return _request<T>(
      path: path,
      method: 'POST',
      query: query,
      dataFactory:
          () => FormData.fromMap(<String, Object>{
            fieldName: MultipartFile.fromStream(
              file.openRead,
              file.length,
              filename: effectiveFilename,
              contentType: mediaType,
            ),
            if (extraFields != null)
              for (final entry in extraFields.entries)
                if (entry.value != null) entry.key: entry.value!,
          }, ListFormat.multi),
      retryOnUnauthorized: retryOnUnauthorized,
      onSendProgress: onProgress,
    );
  }

  static DioMediaType? _resolveMediaType(String? contentType, String fileName) {
    if (contentType != null && contentType.isNotEmpty) {
      try {
        return DioMediaType.parse(contentType);
      } catch (_) {}
    }
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return DioMediaType('image', 'png');
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return DioMediaType('image', 'jpeg');
    }
    if (lower.endsWith('.gif')) return DioMediaType('image', 'gif');
    if (lower.endsWith('.webp')) return DioMediaType('image', 'webp');
    if (lower.endsWith('.bmp')) return DioMediaType('image', 'bmp');
    if (lower.endsWith('.mp4')) return DioMediaType('video', 'mp4');
    if (lower.endsWith('.mov')) return DioMediaType('video', 'quicktime');
    if (lower.endsWith('.mp3')) return DioMediaType('audio', 'mpeg');
    if (lower.endsWith('.amr')) return DioMediaType('audio', 'amr');
    if (lower.endsWith('.m4a')) return DioMediaType('audio', 'mp4');
    if (lower.endsWith('.pdf')) return DioMediaType('application', 'pdf');
    return null;
  }

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
    void Function(int sent, int total)? onSendProgress,
  }) async {
    final traceId = DiagnosticTrace.create('http');
    final stopwatch = Stopwatch()..start();
    final usesStoredAccessToken = headers?.containsKey('Authorization') != true;
    if (usesStoredAccessToken && _globalRefreshInFlight != null) {
      try {
        await _globalRefreshInFlight;
      } catch (_) {
        // If the in-flight refresh failed, let the subsequent token check/refresh handle it.
      }
    }
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
          contentType: dataFactory != null ? null : Headers.jsonContentType,
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
        onSendProgress: onSendProgress,
      );
      if (cancelTag != null) _cancelTokens.remove(cancelTag);
      AppLogger.instance.info(
        '$method ${_logUri(response.realUri)} ${response.statusCode}',
        category: 'http',
        event: 'http_response',
        traceId: traceId,
        context: <String, Object?>{
          'method': method,
          'url': _logUri(response.realUri),
          'query': query,
          'statusCode': response.statusCode,
          'durationMs': stopwatch.elapsedMilliseconds,
          'requestSize': data?.toString().length,
          'responseSize': response.data?.toString().length,
        },
      );
      return _unwrap<T>(response.data);
    } on DioException catch (error) {
      if (cancelTag != null) _cancelTokens.remove(cancelTag);
      if (retryOnUnauthorized &&
          usesStoredAccessToken &&
          accessToken != null &&
          accessToken.isNotEmpty &&
          error.response?.statusCode == 401 &&
          !hasRetriedAfterRefresh) {
        try {
          final inFlight = _globalRefreshInFlight;
          if (inFlight != null) {
            await inFlight;
          } else {
            final currentToken = await _tokenStorage.readAccessToken();
            if (currentToken == accessToken) {
              await _refreshOnce();
            }
          }
        } on TokenRefreshRejectedException catch (error) {
          if (error.code != 'session_signed_out') await _invalidateSession();
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
          onSendProgress: onSendProgress,
        );
      }
      if (retryOnUnauthorized &&
          usesStoredAccessToken &&
          hasRetriedAfterRefresh &&
          error.response?.statusCode == 401) {
        await _invalidateSession();
      }
      AppLogger.instance.error(
        '$method ${_logUri(error.requestOptions.uri)} failed (${error.response?.statusCode ?? 'network'})',
        category: 'http',
        event: 'http_error',
        traceId: traceId,
        error: error,
        stackTrace: error.stackTrace,
        context: <String, Object?>{
          'method': method,
          'url': _logUri(error.requestOptions.uri),
          'query': query,
          'statusCode': error.response?.statusCode,
          'durationMs': stopwatch.elapsedMilliseconds,
          'requestHeaders': error.requestOptions.headers,
          'responseHeaders': error.response?.headers.map,
          'responseData': error.response?.data,
        },
      );
      throw _toApiException(error);
    }
  }

  static String _logUri(Uri uri) {
    final parameters = <String, dynamic>{};
    for (final entry in uri.queryParametersAll.entries) {
      parameters[entry.key] = LogSanitizer.sanitize(
        entry.value,
        key: entry.key,
      );
    }
    return uri
        .replace(
          userInfo: '',
          queryParameters: parameters.isEmpty ? null : parameters,
          query: parameters.isEmpty ? '' : null,
        )
        .toString();
  }

  Future<void> _refreshOnce() {
    final inFlight = _globalRefreshInFlight;
    if (inFlight != null) return inFlight;
    final refresh = _tokenRefresher.refreshAccessToken();
    _globalRefreshInFlight = refresh;
    return refresh.whenComplete(() {
      if (identical(_globalRefreshInFlight, refresh)) {
        _globalRefreshInFlight = null;
      }
    });
  }

  Future<void> _refreshOrClear() async {
    try {
      await _refreshOnce();
    } on TokenRefreshRejectedException catch (error) {
      // A stale refresh belongs to a session already cleared by logout. It must not clear a newer login.
      if (error.code != 'session_signed_out') await _invalidateSession();
      rethrow;
    }
  }

  Future<void> _invalidateSession() {
    final inFlight = _globalSessionInvalidationInFlight;
    if (inFlight != null) return inFlight;
    final invalidation = () async {
      await _tokenRefresher.clearSession();
      await _onSessionInvalidated?.call();
    }();
    _globalSessionInvalidationInFlight = invalidation;
    return invalidation.whenComplete(() {
      if (identical(_globalSessionInvalidationInFlight, invalidation)) {
        _globalSessionInvalidationInFlight = null;
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
    final retrySeconds = int.tryParse(
      error.response?.headers.value("retry-after") ?? "",
    );
    return ApiException(
      message,
      statusCode: error.response?.statusCode,
      code: responseError is Map ? responseError['code']?.toString() : null,
      retryAfter: retrySeconds == null ? null : Duration(seconds: retrySeconds),
    );
  }
}
