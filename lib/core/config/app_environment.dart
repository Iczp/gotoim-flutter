import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppFlavor { development, staging, production }

/// Runtime configuration loaded once during bootstrap.
///
/// Features receive this typed object through Riverpod instead of reading
/// `.env`, `String.fromEnvironment`, or platform APIs themselves.
class AppEnvironment {
  const AppEnvironment._({
    required this.flavor,
    required this.apiBaseUrl,
    required this.appId,
    required this.appName,
    required this.appVersion,
    required this.authBaseUrl,
    required this.authTokenPath,
    required this.authClientId,
    required this.authClientSecret,
    required this.authScope,
    required this.authLoginGrantType,
    required this.authUserInfoPath,
    required this.authIntrospectionPath,
    required this.authRevocationPath,
    required this.signalRBaseUrl,
    required this.signalRHubPath,
    required this.scanLoginHubPath,
    required this.scanLoginSignalRBaseUrl,
    required this.scanLoginTemplate,
    required this.scanLoginFallbackExpires,
    required this.scanLoginAuthBaseUrl,
    required this.scanLoginAuthTokenPath,
    required this.scanLoginAuthClientId,
    required this.scanLoginAuthClientSecret,
    required this.scanLoginAuthScope,
    required this.signalRSkipNegotiation,
    required this.signalRReconnectDelays,
    required this.jsBridgeHarnessUrl,
    required this.jsBridgeUploadUrl,
    required this.jsBridgeUploadAllowedHosts,
    required this.enableNetworkLogging,
    required this.deepLinkCustomSchemes,
    required this.deepLinkAllowedHosts,
  });

  final AppFlavor flavor;
  final String apiBaseUrl;
  final String appId;
  final String appName;
  final String appVersion;
  final String authBaseUrl;
  final String authTokenPath;
  final String authClientId;
  final String authClientSecret;
  final String authScope;
  final String authLoginGrantType;

  final String authUserInfoPath;
  final String authIntrospectionPath;
  final String authRevocationPath;
  final String signalRBaseUrl;
  final String signalRHubPath;
  final String scanLoginHubPath;
  final String scanLoginSignalRBaseUrl;
  final String scanLoginTemplate;
  final Duration scanLoginFallbackExpires;
  final String scanLoginAuthBaseUrl;
  final String scanLoginAuthTokenPath;
  final String scanLoginAuthClientId;
  final String scanLoginAuthClientSecret;
  final String scanLoginAuthScope;
  final bool signalRSkipNegotiation;
  final List<int> signalRReconnectDelays;

  /// Debug-only standalone H5 page used to verify the native JS bridge.
  final String jsBridgeHarnessUrl;

  /// Debug upload endpoint used by the native Bridge and browser file-input
  /// harness flows. It is intentionally separate from the Harness page URL.
  final String jsBridgeUploadUrl;

  /// Explicit allowlist for H5-requested upload destinations.
  final List<String> jsBridgeUploadAllowedHosts;
  final bool enableNetworkLogging;

  /// Allowed custom URL schemes for deep links (e.g. gotoim-dev, gotoim).
  final List<String> deepLinkCustomSchemes;

  /// Allowed HTTPS domain hosts for universal/app links (e.g. gotoim.com).
  final List<String> deepLinkAllowedHosts;

  static AppFlavor parseFlavor(String value) {
    return AppFlavor.values.firstWhere(
      (item) => item.name == value,
      orElse: () => AppFlavor.development,
    );
  }

  factory AppEnvironment.fromDotEnv(AppFlavor flavor) {
    return AppEnvironment._(
      flavor: flavor,
      apiBaseUrl: dotenv.get('API_BASE_URL', fallback: ''),
      appId: dotenv.get('APP_ID', fallback: '__UNI__39F095D'),
      appName: dotenv.get('APP_NAME', fallback: 'Goto IM'),
      appVersion: dotenv.get('APP_VERSION', fallback: '1.0.0'),
      authBaseUrl: dotenv.get('AUTH_BASE_URL', fallback: ''),
      authTokenPath: dotenv.get('AUTH_TOKEN_PATH', fallback: '/connect/token'),
      authClientId: dotenv.get('AUTH_CLIENT_ID', fallback: ''),
      authClientSecret: dotenv.get('AUTH_CLIENT_SECRET', fallback: ''),
      authScope: dotenv.get('AUTH_SCOPE', fallback: ''),
      authLoginGrantType: _nonEmpty(
        dotenv.get('AUTH_LOGIN_GRANT_TYPE', fallback: ''),
        fallback: 'password',
      ),
      authUserInfoPath: dotenv.get(
        'AUTH_USER_INFO_PATH',
        fallback: '/connect/userinfo',
      ),
      authIntrospectionPath: dotenv.get(
        'AUTH_INTROSPECTION_PATH',
        fallback: '/connect/introspect',
      ),
      authRevocationPath: dotenv.get(
        'AUTH_REVOCATION_PATH',
        fallback: '/connect/revocat',
      ),
      signalRBaseUrl: dotenv.get('SIGNALR_BASE_URL', fallback: ''),
      signalRHubPath: dotenv.get(
        'SIGNALR_HUB_PATH',
        fallback: '/signalr-hubs/chat',
      ),
      scanLoginHubPath: dotenv.get(
        'SCAN_LOGIN_HUB_PATH',
        fallback: '/signalr-hubs/scan-login',
      ),
      scanLoginSignalRBaseUrl: _nonEmpty(
        dotenv.get('SCAN_LOGIN_SIGNALR_BASE_URL', fallback: ''),
        fallback: dotenv.get('SIGNALR_BASE_URL', fallback: ''),
      ),
      scanLoginTemplate: _nonEmpty(
        dotenv.get('SCAN_LOGIN_TEMPLATE', fallback: ''),
        fallback: 'gotoim://scan-login?code={code}',
      ),
      scanLoginFallbackExpires: Duration(
        seconds:
            int.tryParse(
              dotenv.get('SCAN_LOGIN_QR_EXPIRES_SECONDS', fallback: '90'),
            ) ??
            90,
      ),
      scanLoginAuthBaseUrl: _nonEmpty(
        dotenv.get('SCAN_LOGIN_AUTH_BASE_URL', fallback: ''),
        fallback: dotenv.get('AUTH_BASE_URL', fallback: ''),
      ),
      scanLoginAuthTokenPath: _nonEmpty(
        dotenv.get('SCAN_LOGIN_AUTH_TOKEN_PATH', fallback: ''),
        fallback: dotenv.get('AUTH_TOKEN_PATH', fallback: '/connect/token'),
      ),
      scanLoginAuthClientId: dotenv.get(
        'SCAN_LOGIN_AUTH_CLIENT_ID',
        fallback: '',
      ),
      scanLoginAuthClientSecret: dotenv.get(
        'SCAN_LOGIN_AUTH_CLIENT_SECRET',
        fallback: '',
      ),
      scanLoginAuthScope: dotenv.get('SCAN_LOGIN_AUTH_SCOPE', fallback: 'IM'),
      signalRSkipNegotiation:
          dotenv.get('SIGNALR_SKIP_NEGOTIATION', fallback: 'true') == 'true',
      signalRReconnectDelays: _parseReconnectDelays(
        dotenv.get(
          'SIGNALR_RECONNECT_DELAYS_MS',
          fallback: '0,2000,10000,30000',
        ),
      ),
      jsBridgeHarnessUrl: dotenv.get('JS_BRIDGE_HARNESS_URL', fallback: ''),
      jsBridgeUploadUrl: dotenv.get('JS_BRIDGE_UPLOAD_URL', fallback: ''),
      jsBridgeUploadAllowedHosts: _parseCsv(
        dotenv.get('JS_BRIDGE_UPLOAD_ALLOWED_HOSTS', fallback: ''),
      ),
      enableNetworkLogging:
          dotenv.get('ENABLE_NETWORK_LOGGING', fallback: 'false') == 'true',
      deepLinkCustomSchemes: _parseCsv(
        dotenv.get('DEEP_LINK_SCHEMES', fallback: 'gotoim-dev,gotoim'),
      ),
      deepLinkAllowedHosts: _parseCsv(
        dotenv.get('DEEP_LINK_ALLOWED_HOSTS', fallback: 'gotoim.com'),
      ),
    );
  }

  static List<int> _parseReconnectDelays(String value) {
    return value
        .split(',')
        .map((item) => int.tryParse(item.trim()))
        .whereType<int>()
        .toList(growable: false);
  }

  static List<String> _parseCsv(String value) => value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);

  static String _nonEmpty(String value, {required String fallback}) {
    return value.trim().isEmpty ? fallback : value;
  }

  String get signalRHubUrl {
    final baseUrl = signalRBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    final hubPath =
        signalRHubPath.startsWith('/') ? signalRHubPath : '/$signalRHubPath';
    return '$baseUrl$hubPath';
  }

  String get scanLoginHubUrl =>
      _urlFor(scanLoginSignalRBaseUrl, scanLoginHubPath);

  String _urlFor(String baseUrl, String path) {
    final normalizedBaseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return '$normalizedBaseUrl$normalizedPath';
  }

  String get authTokenUrl {
    final baseUrl = authBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    final tokenPath =
        authTokenPath.startsWith('/') ? authTokenPath : '/$authTokenPath';
    return '$baseUrl$tokenPath';
  }

  String get scanLoginAuthTokenUrl =>
      _urlFor(scanLoginAuthBaseUrl, scanLoginAuthTokenPath);

  String get authUserInfoUrl {
    final baseUrl = authBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    final path =
        authUserInfoPath.startsWith('/')
            ? authUserInfoPath
            : '/$authUserInfoPath';
    return '$baseUrl$path';
  }

  String get authIntrospectionUrl => _authUrlFor(authIntrospectionPath);

  String get authRevocationUrl => _authUrlFor(authRevocationPath);

  String _authUrlFor(String path) {
    final baseUrl = authBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return '$baseUrl$normalizedPath';
  }

  void validate() {
    if (apiBaseUrl.isEmpty ||
        authBaseUrl.isEmpty ||
        authClientId.isEmpty ||
        signalRBaseUrl.isEmpty ||
        scanLoginSignalRBaseUrl.isEmpty ||
        scanLoginAuthBaseUrl.isEmpty ||
        scanLoginAuthClientId.isEmpty) {
      throw StateError(
        'API_BASE_URL, AUTH_BASE_URL, AUTH_CLIENT_ID, SIGNALR_BASE_URL, '
        'SCAN_LOGIN_SIGNALR_BASE_URL, SCAN_LOGIN_AUTH_BASE_URL, and '
        'SCAN_LOGIN_AUTH_CLIENT_ID '
        'must be configured in '
        '.env.${flavor.name}.',
      );
    }
  }
}

final Provider<AppEnvironment> appEnvironmentProvider =
    Provider<AppEnvironment>(
      (ref) =>
          throw UnimplementedError(
            'AppEnvironment must be provided during bootstrap.',
          ),
    );
