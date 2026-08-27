import 'package:dio/dio.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/device/client_device_context.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/client_credentials_token_storage.dart';
import '../../../core/network/jwt_token_expiry.dart';
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
    required ClientCredentialsTokenStorage clientCredentialsTokenStorage,
    required ClientDeviceContext deviceContext,
  }) : _dio = dio,
       _environment = environment,
       _tokenStorage = tokenStorage,
       _clientCredentialsTokenStorage = clientCredentialsTokenStorage,
       _deviceContext = deviceContext;

  final Dio _dio;
  final AppEnvironment _environment;
  final TokenStorage _tokenStorage;
  final ClientCredentialsTokenStorage _clientCredentialsTokenStorage;
  final ClientDeviceContext _deviceContext;
  Future<AuthSession>? _refreshInFlight;
  final Map<String, Future<String>> _clientCredentialsInFlight = {};

  static Dio createDio(
    AppEnvironment environment,
    ClientDeviceContext deviceContext,
  ) {
    return Dio(
      BaseOptions(
        baseUrl: environment.authBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        headers: deviceContext.requestHeaders,
      ),
    );
  }

  @override
  Future<void> clearSession() => _tokenStorage.clear();

  @override
  Future<void> login({
    required String username,
    required String password,
  }) async {
    final session = await _requestToken(<String, String>{
      'grant_type': _environment.authLoginGrantType,
      'username': username,
      'password': password,
    });
    await _save(session);
  }

  @override
  Future<void> loginWithScanToken(String scanToken) async {
    final session = await _requestToken(<String, String>{
      'grant_type': 'scan-token',
      'scan_token': scanToken,
    });
    await _save(session);
  }

  @override
  Future<String> getClientCredentialsAccessToken() async {
    return _getClientCredentialsToken(
      cacheKey: 'scan-login',
      tokenUrl: _environment.scanLoginAuthTokenUrl,
      clientId: _environment.scanLoginAuthClientId,
      clientSecret: _environment.scanLoginAuthClientSecret,
      scope: _environment.scanLoginAuthScope,
    );
  }

  /// Token for `/api/chat/device/register`; it never shares user-token state.
  Future<String> getDeviceRegistrationAccessToken() =>
      _getClientCredentialsToken(
        cacheKey: 'device-register',
        tokenUrl: _environment.authTokenUrl,
        clientId: _environment.authClientId,
        clientSecret: _environment.authClientSecret,
        scope: 'IM',
      );

  Future<String> _getClientCredentialsToken({
    required String cacheKey,
    required String tokenUrl,
    required String clientId,
    required String clientSecret,
    required String scope,
  }) async {
    final stored = await _clientCredentialsTokenStorage.readValidAccessToken(
      cacheKey,
    );
    if (stored != null) return stored;
    return _clientCredentialsInFlight[cacheKey] ??= _requestClientCredentials(
      cacheKey: cacheKey,
      tokenUrl: tokenUrl,
      clientId: clientId,
      clientSecret: clientSecret,
      scope: scope,
    ).whenComplete(() => _clientCredentialsInFlight.remove(cacheKey));
  }

  Future<String> _requestClientCredentials({
    required String cacheKey,
    required String tokenUrl,
    required String clientId,
    required String clientSecret,
    required String scope,
  }) async {
    final session = await _requestToken(
      const <String, String>{'grant_type': 'client_credentials'},
      tokenUrl: tokenUrl,
      clientId: clientId,
      clientSecret: clientSecret,
      scope: scope,
    );
    // OpenIddict normally returns expires_in, but it is optional in the DTO.
    // Never invent a lifetime: without it the token is returned for this call
    // and will be acquired again next time instead of being persisted stale.
    final expiresIn = session.expiresIn;
    if (expiresIn != null) {
      await _clientCredentialsTokenStorage.save(
        cacheKey,
        accessToken: session.accessToken,
        expiresIn: expiresIn,
      );
    }
    return session.accessToken;
  }

  @override
  Future<Map<String, dynamic>> getUserInfo() async {
    final accessToken = await _tokenStorage.readAccessToken();
    if (accessToken == null || accessToken.isEmpty) {
      throw const ApiException('尚未登录，无法请求用户信息。');
    }
    try {
      final response = await _dio.post<dynamic>(
        _environment.authUserInfoUrl,
        data: const <String, String>{},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: <String, String>{
            ..._deviceContext.requestHeaders,
            'Authorization': 'Bearer $accessToken',
          },
        ),
      );
      if (response.data is! Map) {
        throw const ApiException('用户信息接口返回了无效数据。');
      }
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (error) {
      final body = error.response?.data;
      final message =
          body is Map && body['error_description'] != null
              ? body['error_description'].toString()
              : '用户信息请求失败。';
      throw ApiException(message, statusCode: error.response?.statusCode);
    }
  }

  @override
  Future<Map<String, dynamic>> introspect(RevocationTokenType tokenType) async {
    final token = await _readToken(tokenType);
    if (token == null || token.isEmpty) {
      throw const ApiException('没有可供检查的 Token。');
    }
    final response = await _postAuthForm(
      _environment.authIntrospectionUrl,
      <String, String>{'token': token},
    );
    if (response is! Map) throw const ApiException('Token 检查接口返回了无效数据。');
    return Map<String, dynamic>.from(response);
  }

  @override
  Future<void> logout() async {
    try {
      await Future.wait<void>(<Future<void>>[
        revoke(RevocationTokenType.accessToken),
        revoke(RevocationTokenType.refreshToken),
      ]);
    } catch (_) {
      // Follow UniApp semantics: local logout must still complete.
    } finally {
      await clearSession();
    }
  }

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
  Future<bool> restoreSession() async {
    final accessToken = await _tokenStorage.readAccessToken();
    if (accessToken == null || accessToken.isEmpty) return false;
    if (!shouldRefreshJwt(accessToken)) return true;
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      await clearSession();
      return false;
    }
    try {
      await refreshSession();
      return true;
    } catch (_) {
      await clearSession();
      return false;
    }
  }

  @override
  Future<void> revoke(RevocationTokenType tokenType) async {
    final token = await _readToken(tokenType);
    if (token == null || token.isEmpty) return;
    await _postAuthForm(_environment.authRevocationUrl, <String, String>{
      'token_type_hint':
          tokenType == RevocationTokenType.accessToken
              ? 'access_token'
              : 'refresh_token',
      'token': token,
    });
  }

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
    final completedSession =
        session.refreshToken.isEmpty
            ? AuthSession(
              accessToken: session.accessToken,
              refreshToken: refreshToken,
              expiresIn: session.expiresIn,
            )
            : session;
    await _save(completedSession);
    return completedSession;
  }

  Future<AuthSession> _requestToken(
    Map<String, String> fields, {
    String? tokenUrl,
    String? clientId,
    String? clientSecret,
    String? scope,
  }) async {
    try {
      final response = await _postAuthForm(
        tokenUrl ?? _environment.authTokenUrl,
        fields,
        includeScope: true,
        clientId: clientId,
        clientSecret: clientSecret,
        scope: scope,
      );
      if (response is! Map) {
        throw const ApiException('Invalid token response.');
      }
      return AuthSession.fromJson(Map<String, dynamic>.from(response));
    } on DioException catch (error) {
      final body = error.response?.data;
      final message =
          body is Map && body['error_description'] != null
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

  Future<String?> _readToken(RevocationTokenType tokenType) {
    return tokenType == RevocationTokenType.accessToken
        ? _tokenStorage.readAccessToken()
        : _tokenStorage.readRefreshToken();
  }

  Future<Object?> _postAuthForm(
    String url,
    Map<String, String> fields, {
    bool includeScope = false,
    String? clientId,
    String? clientSecret,
    String? scope,
  }) async {
    final response = await _dio.post<Object?>(
      url,
      data: <String, String>{
        'client_id': clientId ?? _environment.authClientId,
        if ((clientSecret ?? _environment.authClientSecret).isNotEmpty)
          'client_secret': clientSecret ?? _environment.authClientSecret,
        if (includeScope && (scope ?? _environment.authScope).isNotEmpty)
          'scope': scope ?? _environment.authScope,
        ...fields,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    return response.data;
  }
}
