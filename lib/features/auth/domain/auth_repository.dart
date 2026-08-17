import 'auth_session.dart';

enum RevocationTokenType { accessToken, refreshToken }

abstract class AuthRepository {
  Future<bool> restoreSession();

  Future<void> login({required String username, required String password});

  Future<void> logout();

  Future<AuthSession> refreshSession();

  Future<Map<String, dynamic>> getUserInfo();

  Future<Map<String, dynamic>> introspect(RevocationTokenType tokenType);

  Future<void> revoke(RevocationTokenType tokenType);
}
