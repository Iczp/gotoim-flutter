/// Implemented by authentication infrastructure and used by [DioApiClient].
///
/// Keeping this boundary small prevents the HTTP client from knowing OAuth
/// grant details, while allowing all unauthorized requests to share one refresh.
abstract class TokenRefresher {
  Future<void> refreshAccessToken();

  Future<void> clearSession();
}
