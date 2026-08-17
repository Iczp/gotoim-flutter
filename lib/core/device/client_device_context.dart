import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../config/app_environment.dart';
import '../platform/platform_contract.dart';

/// Stable, non-sensitive client/device metadata shared by HTTP and SignalR.
///
/// It intentionally has no feature or UI dependency. Native device details and
/// push registration can later be supplied by a platform adapter.
class ClientDeviceContext {
  const ClientDeviceContext({
    required this.appId,
    required this.appName,
    required this.appVersion,
    required this.deviceId,
    required this.deviceType,
    required this.platform,
    required this.brand,
    required this.model,
    required this.browser,
    required this.pushClientId,
  });

  final String appId;
  final String appName;
  final String appVersion;
  final String deviceId;
  final String deviceType;
  final String platform;
  final String brand;
  final String model;
  final String browser;
  final String pushClientId;

  Map<String, String> get requestHeaders => <String, String>{
        'Accept': '*/*',
        'App-Device-Id': deviceId,
        'App-Device-Type': deviceType,
        'App-Id': appId,
        'App-Version': appVersion,
      };

  Map<String, String> get signalRQueryParameters => <String, String>{
        'appId': appId,
        'appName': appName,
        'deviceId': deviceId,
        'deviceType': deviceType,
        'pushClientId': pushClientId,
        'brand': brand,
        'model': model,
        'platform': platform,
        'browser': browser,
      };
}

class ClientDeviceContextFactory {
  ClientDeviceContextFactory({FlutterSecureStorage? storage, Uuid? uuid})
      : _storage = storage ?? const FlutterSecureStorage(),
        _uuid = uuid ?? const Uuid();

  static const _deviceIdKey = 'gotoim.device-id.v1';

  final FlutterSecureStorage _storage;
  final Uuid _uuid;

  Future<ClientDeviceContext> create({
    required AppEnvironment environment,
    required PlatformFacade platformFacade,
  }) async {
    var deviceId = await _storage.read(key: _deviceIdKey);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = _uuid.v4();
      await _storage.write(key: _deviceIdKey, value: deviceId);
    }
    final kind = platformFacade.kind.name;
    return ClientDeviceContext(
      appId: environment.appId,
      appName: environment.appName,
      appVersion: environment.appVersion,
      deviceId: deviceId,
      deviceType: platformFacade.isWeb ? 'web' : kind,
      platform: kind,
      brand: '',
      model: '',
      browser: platformFacade.isWeb ? 'web' : '',
      pushClientId: '',
    );
  }
}

final clientDeviceContextProvider = Provider<ClientDeviceContext>(
  (ref) => throw UnimplementedError(
    'ClientDeviceContext must be provided during bootstrap.',
  ),
);
