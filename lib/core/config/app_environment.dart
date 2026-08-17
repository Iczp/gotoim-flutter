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
    required this.authBaseUrl,
    required this.authTokenPath,
    required this.authClientId,
    required this.authScope,
    required this.authLoginGrantType,
    required this.signalRBaseUrl,
    required this.signalRHubPath,
    required this.signalRSkipNegotiation,
    required this.signalRReconnectDelays,
    required this.enableNetworkLogging,
  });

  final AppFlavor flavor;
  final String apiBaseUrl;
  final String authBaseUrl;
  final String authTokenPath;
  final String authClientId;
  final String authScope;
  final String authLoginGrantType;
  final String signalRBaseUrl;
  final String signalRHubPath;
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
      authBaseUrl: dotenv.get('AUTH_BASE_URL', fallback: ''),
      authTokenPath: dotenv.get('AUTH_TOKEN_PATH', fallback: '/connect/token'),
      authClientId: dotenv.get('AUTH_CLIENT_ID', fallback: ''),
      authScope: dotenv.get('AUTH_SCOPE', fallback: ''),
      authLoginGrantType:
          dotenv.get('AUTH_LOGIN_GRANT_TYPE', fallback: 'password'),
      signalRBaseUrl: dotenv.get('SIGNALR_BASE_URL', fallback: ''),
      signalRHubPath:
          dotenv.get('SIGNALR_HUB_PATH', fallback: '/signalr-hubs/chat'),
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

  String get signalRHubUrl {
    final baseUrl = signalRBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    final hubPath =
        signalRHubPath.startsWith('/') ? signalRHubPath : '/$signalRHubPath';
    return '$baseUrl$hubPath';
  }

  String get authTokenUrl {
    final baseUrl = authBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    final tokenPath =
        authTokenPath.startsWith('/') ? authTokenPath : '/$authTokenPath';
    return '$baseUrl$tokenPath';
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
