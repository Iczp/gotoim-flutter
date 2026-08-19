/// Secure credential boundary. Infrastructure implementations may use platform
/// plugins; feature and UI code only depend on this contract.
abstract class TokenStorage {
  Future<String?> readAccessToken();

  Future<String?> readRefreshToken();

  Future<void> save({
    required String accessToken,
    required String refreshToken,
  });

  Future<void> clear();

  Future<bool> hasToken() async =>
      (await readAccessToken())?.isNotEmpty == true;
}
