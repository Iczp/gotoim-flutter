class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.statusCode,
    this.code,
    this.retryAfter,
  });

  final String message;
  final int? statusCode;
  final String? code;
  final Duration? retryAfter;

  @override
  String toString() => 'ApiException($statusCode, $code): $message';
}
