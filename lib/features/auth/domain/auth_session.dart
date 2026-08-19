class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
  });

  final String accessToken;
  final String refreshToken;
  final Duration? expiresIn;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final accessToken =
        (json['access_token'] ?? json['accessToken'] ?? '').toString();
    if (accessToken.isEmpty) {
      throw const FormatException(
        'The token response does not contain access_token.',
      );
    }
    return AuthSession(
      accessToken: accessToken,
      refreshToken:
          (json['refresh_token'] ?? json['refreshToken'] ?? '').toString(),
      expiresIn: _parseExpiresIn(json['expires_in'] ?? json['expiresIn']),
    );
  }

  static Duration? _parseExpiresIn(Object? value) {
    final seconds = value is num ? value.toInt() : int.tryParse('$value');
    return seconds == null ? null : Duration(seconds: seconds);
  }
}
