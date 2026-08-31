/// Transport boundary used by repositories. Feature/UI code must not use Dio
/// or another HTTP client directly.
abstract class ApiClient {
  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    bool retryOnUnauthorized = true,
  });

  Future<T> post<T>(
    String path, {
    Map<String, Object?>? query,
    Object? data,
    Map<String, String>? headers,
    bool retryOnUnauthorized = true,
  });

  Future<T> postMultipart<T>(
    String path, {
    Map<String, Object?>? query,
    Map<String, Object?>? extraFields,
    required MultipartUploadFile file,
    String fieldName = 'file',
    void Function(int sent, int total)? onProgress,
    bool retryOnUnauthorized = true,
  });

  Future<void> cancelByTag(Object tag);

  Future<List<int>> getBytes(
    String path, {
    Object? cancelTag,
    void Function(int received, int total)? onProgress,
  }) =>
      throw UnsupportedError('Binary download is not supported.');
}

class MultipartUploadFile {
  const MultipartUploadFile({
    required this.name,
    required this.length,
    required this.openRead,
  });

  final String name;
  final int length;
  final Stream<List<int>> Function() openRead;
}
