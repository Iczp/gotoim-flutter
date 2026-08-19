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

  @override
  Future<void> clear() async {
    await Future.wait(<Future<void>>[
      _storage.delete(key: _accessTokenKey),
      _storage.delete(key: _refreshTokenKey),
    ]);
  }

  @override
  Future<String?> readAccessToken() => _storage.read(key: _accessTokenKey);

  @override
  Future<String?> readRefreshToken() => _storage.read(key: _refreshTokenKey);

  @override
  Future<bool> hasToken() async =>
      (await readAccessToken())?.isNotEmpty == true;

  @override
  Future<void> save({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait(<Future<void>>[
      _storage.write(key: _accessTokenKey, value: accessToken),
      _storage.write(key: _refreshTokenKey, value: refreshToken),
    ]);
  }
}
