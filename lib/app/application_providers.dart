import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_environment.dart';
import '../core/device/client_device_context.dart';
import '../core/network/api_client.dart';
import '../core/network/dio_api_client.dart';
import '../core/notifications/local_notification_service.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/data/openid_connect_auth_repository.dart';

/// Composition-root providers. Feature pages depend on repositories/use cases,
/// not on this transport provider or Dio directly.
final apiClientProvider = Provider<ApiClient>((ref) {
  final environment = ref.watch(appEnvironmentProvider);
  final authRepository = ref.watch(authRepositoryProvider);
  return DioApiClient(
    dio: Dio(
      BaseOptions(
        baseUrl: environment.apiBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
      ),
    ),
    tokenStorage: ref.watch(tokenStorageProvider),
    tokenRefresher: authRepository as OpenIdConnectAuthRepository,
    deviceContext: ref.watch(clientDeviceContextProvider),
  );
});

/// 由 bootstrap 创建并覆写，保证通知点击回调在应用启动时即可注册。
final localNotificationServiceProvider = Provider<LocalNotificationService>(
  (ref) =>
      throw UnimplementedError(
        'LocalNotificationService must be provided at bootstrap.',
      ),
);
