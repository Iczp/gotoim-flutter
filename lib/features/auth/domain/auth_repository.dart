import 'auth_session.dart';

abstract class AuthRepository {
  Future<bool> restoreSession();

  Future<void> login({required String username, required String password});

  Future<void> logout();

  Future<AuthSession> refreshSession();

  Future<Map<String, dynamic>> getUserInfo();
}
