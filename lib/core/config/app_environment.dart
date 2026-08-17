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
    required this.signalRBaseUrl,
    required this.enableNetworkLogging,
  });

  final AppFlavor flavor;
  final String apiBaseUrl;
  final String signalRBaseUrl;
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
      signalRBaseUrl: dotenv.get('SIGNALR_BASE_URL', fallback: ''),
      enableNetworkLogging:
          dotenv.get('ENABLE_NETWORK_LOGGING', fallback: 'false') == 'true',
    );
  }

  void validate() {
    if (apiBaseUrl.isEmpty || signalRBaseUrl.isEmpty) {
      throw StateError(
        'API_BASE_URL and SIGNALR_BASE_URL must be configured in '
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
