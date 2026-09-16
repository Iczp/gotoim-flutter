import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_environment.dart';
import '../core/capabilities/client_capability_service.dart';
import '../core/device/client_device_context.dart';
import '../core/device/device_registration_api.dart';
import '../core/database/unified_database.dart';
import '../core/jsbridge/js_api_dispatcher.dart';
import '../core/network/api_client.dart';
import '../core/network/dio_api_client.dart';
import '../core/devtools/remote_debug/remote_dev_server.dart';
import '../core/notifications/local_notification_service.dart';
import '../features/auth/application/auth_controller.dart';
import '../core/network/abp/abp_application_configuration_dto.dart';
import '../core/network/abp/abp_configuration_api.dart';
import '../core/network/abp/abp_configuration_repository.dart';
import '../core/network/abp/abp_current_user.dart';
import '../features/auth/data/openid_connect_auth_repository.dart';

/// Composition-root providers. Feature pages depend on repositories/use cases,
/// not on this transport provider or Dio directly.
final Provider<ApiClient> apiClientProvider = Provider<ApiClient>((ref) {
  final environment = ref.watch(appEnvironmentProvider);
  final authRepository = ref.watch(authRepositoryProvider);
  return DioApiClient(
    dio: Dio(
      BaseOptions(
        baseUrl: environment.apiBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        contentType: Headers.jsonContentType,
      ),
    ),
    tokenStorage: ref.watch(tokenStorageProvider),
    tokenRefresher: authRepository as OpenIdConnectAuthRepository,
    deviceContext: ref.watch(clientDeviceContextProvider),
    // A request may discover an expired token while AuthController itself is
    // still being constructed. Defer the read so invalidation cannot form an
    // ApiClient -> AuthController -> ApiClient provider cycle.
    onSessionInvalidated: () async {
      await Future<void>.delayed(Duration.zero);
      await ref.read(authControllerProvider.notifier).sessionInvalidated();
    },
  );
});

final deviceRegistrationApiProvider = Provider<DeviceRegistrationApi>((ref) {
  return DeviceRegistrationApi(
    apiClient: ref.watch(apiClientProvider),
    capabilities: ref.watch(clientCapabilityServiceProvider),
    deviceContext: ref.watch(clientDeviceContextProvider),
    environment: ref.watch(appEnvironmentProvider),
    readClientCredentialsToken:
        (ref.watch(authRepositoryProvider) as OpenIdConnectAuthRepository)
            .getDeviceRegistrationAccessToken,
  );
});

/// 由 bootstrap 创建并覆写，保证通知点击回调在应用启动时即可注册。
final localNotificationServiceProvider = Provider<LocalNotificationService>(
  (ref) =>
      throw UnimplementedError(
        'LocalNotificationService must be provided at bootstrap.',
      ),
);

/// Unified application entry point for client/platform APIs.
final clientCapabilityServiceProvider = Provider<ClientCapabilityService>(
  (ref) =>
      throw UnimplementedError(
        'ClientCapabilityService must be provided at bootstrap.',
      ),
);

/// JSON request/response dispatcher used by WebView adapters and diagnostics.
final jsApiDispatcherProvider = Provider<JsApiDispatcher>(
  (ref) =>
      throw UnimplementedError(
        'JsApiDispatcher must be provided at bootstrap.',
      ),
);

/// The single SQL database shared by native and Web clients.
final unifiedDatabaseProvider = Provider<UnifiedDatabase>(
  (ref) =>
      throw UnimplementedError(
        'UnifiedDatabase must be provided at bootstrap.',
      ),
);

/// Development-only LAN Remote DevTools server. Bootstrap supplies its single
/// instance; it starts only after an explicit action in diagnostics.
final remoteDevServerProvider = Provider<RemoteDevServer>(
  (ref) => RemoteDevServer(),
);

/// ABP Application Configuration API.
final Provider<AbpConfigurationApi> abpConfigurationApiProvider =
    Provider<AbpConfigurationApi>((ref) {
      return AbpConfigurationApi(ref.watch(apiClientProvider));
    });

/// ABP Application Configuration Repository with SQLite caching.
final Provider<AbpConfigurationRepository> abpConfigurationRepositoryProvider =
    Provider<AbpConfigurationRepository>((ref) {
      return AbpConfigurationRepository(
        api: ref.watch(abpConfigurationApiProvider),
        database: ref.watch(unifiedDatabaseProvider),
      );
    });

/// Current logged-in user from ABP `/api/abp/application-configuration`.
final Provider<AbpCurrentUser?> currentUserProvider = Provider<AbpCurrentUser?>(
  (ref) {
    return ref.watch(authControllerProvider).currentUser;
  },
);

/// Latest application configuration from ABP `/api/abp/application-configuration`.
final Provider<AbpApplicationConfigurationDto?> abpConfigurationProvider =
    Provider<AbpApplicationConfigurationDto?>((ref) {
      return ref.watch(authControllerProvider).applicationConfiguration;
    });
