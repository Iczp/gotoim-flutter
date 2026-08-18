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
    required this.signalRSkipNegotiation,
    required this.signalRReconnectDelays,
    required this.enableNetworkLogging,
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
  final bool signalRSkipNegotiation;
  final List<int> signalRReconnectDelays;
  final bool enableNetworkLogging;

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
      authUserInfoPath:
          dotenv.get('AUTH_USER_INFO_PATH', fallback: '/connect/userinfo'),
      authIntrospectionPath: dotenv.get('AUTH_INTROSPECTION_PATH',
          fallback: '/connect/introspect'),
      authRevocationPath:
          dotenv.get('AUTH_REVOCATION_PATH', fallback: '/connect/revocat'),
      signalRBaseUrl: dotenv.get('SIGNALR_BASE_URL', fallback: ''),
      signalRHubPath:
          dotenv.get('SIGNALR_HUB_PATH', fallback: '/signalr-hubs/chat'),
      scanLoginHubPath: dotenv.get(
        'SCAN_LOGIN_HUB_PATH',
        fallback: '/signalr-hubs/scan-login',
      ),
      signalRSkipNegotiation:
          dotenv.get('SIGNALR_SKIP_NEGOTIATION', fallback: 'true') == 'true',
      signalRReconnectDelays: _parseReconnectDelays(
        dotenv.get(
          'SIGNALR_RECONNECT_DELAYS_MS',
          fallback: '0,2000,10000,30000',
        ),
      ),
      enableNetworkLogging:
          dotenv.get('ENABLE_NETWORK_LOGGING', fallback: 'false') == 'true',
    );
  }

  static List<int> _parseReconnectDelays(String value) {
    return value
        .split(',')
        .map((item) => int.tryParse(item.trim()))
        .whereType<int>()
        .toList(growable: false);
  }

  static String _nonEmpty(String value, {required String fallback}) {
    return value.trim().isEmpty ? fallback : value;
  }

  String get signalRHubUrl {
    final baseUrl = signalRBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    final hubPath =
        signalRHubPath.startsWith('/') ? signalRHubPath : '/$signalRHubPath';
    return '$baseUrl$hubPath';
  }

  String get scanLoginHubUrl => _signalRUrlFor(scanLoginHubPath);

  String _signalRUrlFor(String path) {
    final baseUrl = signalRBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return '$baseUrl$normalizedPath';
  }

  String get authTokenUrl {
    final baseUrl = authBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    final tokenPath =
        authTokenPath.startsWith('/') ? authTokenPath : '/$authTokenPath';
    return '$baseUrl$tokenPath';
  }

  String get authUserInfoUrl {
    final baseUrl = authBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    final path = authUserInfoPath.startsWith('/')
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
        signalRBaseUrl.isEmpty) {
      throw StateError(
        'API_BASE_URL, AUTH_BASE_URL, AUTH_CLIENT_ID, and SIGNALR_BASE_URL '
        'must be configured in '
        '.env.${flavor.name}.',
      );
    }
  }
}

final Provider<AppEnvironment> appEnvironmentProvider =
    Provider<AppEnvironment>(
  (ref) => throw UnimplementedError(
    'AppEnvironment must be provided during bootstrap.',
  ),
);
