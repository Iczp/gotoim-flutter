class LogSanitizer {
  static const _sensitiveKeys = <String>{
    'authorization',
    'cookie',
    'access_token',
    'refresh_token',
    'id_token',
    'password',
    'secret',
    'client_secret',
    'verificationcode',
    'code',
  };

  static Object? sanitize(Object? value, {String? key}) {
    if (key != null && _isSensitive(key)) {
      return '***';
    }
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          entry.key.toString():
              sanitize(entry.value, key: entry.key.toString()),
      };
    }
    if (value is Iterable) {
      return value.map((item) => sanitize(item)).toList();
    }
    if (value is String && value.length > 4096) {
      return '${value.substring(0, 4096)}…[truncated]';
    }
    return value;
  }

  static bool _isSensitive(String key) {
    final normalized = key.toLowerCase().replaceAll('-', '_');
    return _sensitiveKeys.contains(normalized) ||
        normalized.contains('token') ||
        normalized.contains('password');
  }
}
