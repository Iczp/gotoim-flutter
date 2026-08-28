/// Implemented by authentication infrastructure and used by [DioApiClient].
///
/// Keeping this boundary small prevents the HTTP client from knowing OAuth
/// grant details, while allowing all unauthorized requests to share one refresh.
abstract class TokenRefresher {
  Future<void> refreshAccessToken();

  Future<void> clearSession();
}

/// The authorization server definitively rejected the stored refresh session.
/// Connectivity, timeout and server errors must not use this exception.
class TokenRefreshRejectedException implements Exception {
  const TokenRefreshRejectedException(this.message, {this.code});
  final String message;
  final String? code;

  @override
  String toString() => 'TokenRefreshRejectedException($code): $message';
}
