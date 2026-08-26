import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'token_storage.dart';

/// Credential storage implementation. Feature/UI code must use [TokenStorage]
/// and must never access this plugin directly.
class SecureTokenStorage implements TokenStorage {
  SecureTokenStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _accessTokenKey = 'gotoim.access-token.v1';
  static const _refreshTokenKey = 'gotoim.refresh-token.v1';

  final FlutterSecureStorage _storage;
  String? _cachedAccessToken;
  String? _cachedRefreshToken;

  @override
  Future<void> clear() async {
    _cachedAccessToken = null;
    _cachedRefreshToken = null;
    try {
      await Future.wait(<Future<void>>[
        _storage.delete(key: _accessTokenKey),
        _storage.delete(key: _refreshTokenKey),
      ]);
    } catch (_) {}
  }

  @override
  Future<String?> readAccessToken() async {
    try {
      final value = await _storage.read(key: _accessTokenKey);
      if (value != null && value.isNotEmpty) {
        _cachedAccessToken = value;
      }
      return value ?? _cachedAccessToken;
    } catch (_) {
      return _cachedAccessToken;
    }
  }

  @override
  Future<String?> readRefreshToken() async {
    try {
      final value = await _storage.read(key: _refreshTokenKey);
      if (value != null && value.isNotEmpty) {
        _cachedRefreshToken = value;
      }
      return value ?? _cachedRefreshToken;
    } catch (_) {
      return _cachedRefreshToken;
    }
  }

  @override
  Future<bool> hasToken() async =>
      (await readAccessToken())?.isNotEmpty == true;

  @override
  Future<void> save({
    required String accessToken,
    required String refreshToken,
  }) async {
    _cachedAccessToken = accessToken;
    _cachedRefreshToken = refreshToken;
    try {
      await Future.wait(<Future<void>>[
        _storage.write(key: _accessTokenKey, value: accessToken),
        _storage.write(key: _refreshTokenKey, value: refreshToken),
      ]);
    } catch (_) {}
  }
}
