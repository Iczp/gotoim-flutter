import 'package:dio/dio.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/token_refresher.dart';
import '../../../core/network/token_storage.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_session.dart';

/// OpenIddict password/refresh-token adapter matching the current UniApp IM
/// client. No client secret is sent from this public client.
class OpenIdConnectAuthRepository implements AuthRepository, TokenRefresher {
  OpenIdConnectAuthRepository({
    required Dio dio,
    required AppEnvironment environment,
    required TokenStorage tokenStorage,
  })  : _dio = dio,
        _environment = environment,
        _tokenStorage = tokenStorage;

  final Dio _dio;
  final AppEnvironment _environment;
  final TokenStorage _tokenStorage;
  Future<AuthSession>? _refreshInFlight;

  static Dio createDio(AppEnvironment environment) {
    return Dio(
      BaseOptions(
        baseUrl: environment.authBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
      ),
    );
  }

  @override
  Future<void> clearSession() => _tokenStorage.clear();

  @override
  Future<void> login(
      {required String username, required String password}) async {
    final session = await _requestToken(<String, String>{
      'grant_type': _environment.authLoginGrantType,
      'username': username,
      'password': password,
    });
    await _save(session);
  }

  @override
  Future<void> logout() => clearSession();

  @override
  Future<void> refreshAccessToken() async {
    await refreshSession();
  }

  @override
  Future<AuthSession> refreshSession() {
    return _refreshInFlight ??= _refresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  @override
  Future<bool> restoreSession() => _tokenStorage.hasToken();

  Future<AuthSession> _refresh() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      throw const ApiException('No refresh token is available.');
    }
    final session = await _requestToken(<String, String>{
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
    });
    // Some providers do not rotate refresh tokens. Keep the prior one then.
    final completedSession = session.refreshToken.isEmpty
        ? AuthSession(
            accessToken: session.accessToken,
            refreshToken: refreshToken,
            expiresIn: session.expiresIn,
          )
        : session;
    await _save(completedSession);
    return completedSession;
  }

  Future<AuthSession> _requestToken(Map<String, String> fields) async {
    try {
      final response = await _dio.post<dynamic>(
        _environment.authTokenUrl,
        data: <String, String>{
          'client_id': _environment.authClientId,
          if (_environment.authScope.isNotEmpty)
            'scope': _environment.authScope,
          ...fields,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      if (response.data is! Map) {
        throw const ApiException('Invalid token response.');
      }
      return AuthSession.fromJson(
          Map<String, dynamic>.from(response.data as Map));
    } on DioException catch (error) {
      final body = error.response?.data;
      final message = body is Map && body['error_description'] != null
          ? body['error_description'].toString()
          : 'Login failed. Please check your network and credentials.';
      throw ApiException(message, statusCode: error.response?.statusCode);
    }
  }

  Future<void> _save(AuthSession session) {
    return _tokenStorage.save(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
    );
  }
}
