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

  Future<void> cancelByTag(Object tag);
}
