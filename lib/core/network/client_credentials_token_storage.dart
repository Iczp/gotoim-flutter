import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Separate storage for machine/client tokens. It is deliberately independent
/// from [TokenStorage], which holds the signed-in user's token pair.
class ClientCredentialsTokenStorage {
  ClientCredentialsTokenStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _keyPrefix = 'gotoim.client-credentials.v1.';
  final FlutterSecureStorage _storage;
  final Map<String, ClientCredentialsToken> _cache = {};

  Future<String?> readValidAccessToken(String cacheKey) async {
    ClientCredentialsToken? token = _cache[cacheKey];
    try {
      final raw = await _storage.read(key: '$_keyPrefix$cacheKey');
      if (raw != null) token = ClientCredentialsToken.fromJson(raw);
    } catch (_) {}
    if (token == null || !token.isValid) return null;
    _cache[cacheKey] = token;
    return token.accessToken;
  }

  Future<void> save(
    String cacheKey, {
    required String accessToken,
    required Duration expiresIn,
  }) async {
    final token = ClientCredentialsToken(
      accessToken: accessToken,
      expiresAt: DateTime.now().add(expiresIn),
    );
    _cache[cacheKey] = token;
    try {
      await _storage.write(key: '$_keyPrefix$cacheKey', value: token.toJson());
    } catch (_) {}
  }
}

class ClientCredentialsToken {
  const ClientCredentialsToken({
    required this.accessToken,
    required this.expiresAt,
  });

  final String accessToken;
  final DateTime expiresAt;

  /// Refresh slightly early to avoid using a token that expires in transit.
  bool get isValid =>
      accessToken.isNotEmpty &&
      expiresAt.isAfter(DateTime.now().add(const Duration(seconds: 30)));

  String toJson() => jsonEncode(<String, String>{
    'accessToken': accessToken,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  });

  static ClientCredentialsToken? fromJson(String value) {
    try {
      final json = jsonDecode(value) as Map<String, dynamic>;
      final accessToken = json['accessToken']?.toString() ?? '';
      final expiresAt = DateTime.tryParse(json['expiresAt']?.toString() ?? '');
      return expiresAt == null
          ? null
          : ClientCredentialsToken(
            accessToken: accessToken,
            expiresAt: expiresAt,
          );
    } catch (_) {
      return null;
    }
  }
}
