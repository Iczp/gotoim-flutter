import 'auth_session.dart';

enum RevocationTokenType { accessToken, refreshToken }

abstract class AuthRepository {
  Future<bool> restoreSession();

  Future<void> login({required String username, required String password});

  Future<void> register({
    required String username,
    required String password,
    String? emailAddress,
  });

  Future<void> loginWithScanToken(String scanToken);

  /// Gets a short-lived public-client token used only to establish an
  /// unauthenticated scan-login challenge. It is stored separately from the
  /// signed-in user's credential pair.
  Future<String> getClientCredentialsAccessToken();

  Future<void> logout();

  Future<AuthSession> refreshSession();

  Future<Map<String, dynamic>> getUserInfo();

  Future<Map<String, dynamic>> introspect(RevocationTokenType tokenType);

  Future<void> revoke(RevocationTokenType tokenType);
}
