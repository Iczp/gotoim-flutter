import 'dart:convert';

import '../capabilities/client_capability_service.dart';
import '../capabilities/client_capability_models.dart';
import '../config/app_environment.dart';
import '../network/api_client.dart';
import 'client_device_context.dart';

/// Registers the current installation with the chat backend.  This endpoint
/// is authenticated with HTTP Basic, rather than the user's Bearer token.
class DeviceRegistrationApi {
  DeviceRegistrationApi({
    required ApiClient apiClient,
    required ClientCapabilityService capabilities,
    required ClientDeviceContext deviceContext,
    required AppEnvironment environment,
  })  : _apiClient = apiClient,
        _capabilities = capabilities,
        _deviceContext = deviceContext,
        _environment = environment;

  final ApiClient _apiClient;
  final ClientCapabilityService _capabilities;
  final ClientDeviceContext _deviceContext;
  final AppEnvironment _environment;

  Future<Map<String, Object?>> collectPayload({String? name}) async {
    final results = await Future.wait<Object>([
      _capabilities.getSystemInfo(),
      _capabilities.getDeviceInfo(),
      _capabilities.getNetworkType(),
    ]);
    final system = results[0] as ClientSystemInfo;
    final device = results[1] as ClientDeviceInfo;
    final network = results[2] as ClientNetworkStatus;
    final safeAreaInsets = jsonEncode(<String, num>{
      'top': system.safeAreaTop,
      'right': system.safeAreaRight,
      'bottom': system.safeAreaBottom,
      'left': system.safeAreaLeft,
    });
    final platform = _deviceContext.platform;
    final appVersionCode = int.tryParse(
          _environment.appVersion.split('.').first,
        ) ??
        0;

    // Keep UniApp-compatible names. Values unavailable to Flutter on a given
    // platform are sent as empty values instead of inventing device metadata.
    return <String, Object?>{
      'name': name?.trim().isNotEmpty == true
          ? name!.trim()
          : (_deviceContext.appName),
      'deviceId': _deviceContext.deviceId,
      'platform': platform,
      'appId': _environment.appId,
      'sdkVersion': '',
      'app': _environment.appName,
      'appLanguage': system.locale,
      'appName': _environment.appName,
      'appVersion': _environment.appVersion,
      'appVersionCode': appVersionCode,
      'appWgtVersion': '',
      'brand': device.brand ?? _deviceContext.brand,
      'browserName': device.browser ?? _deviceContext.browser,
      'browserVersion': '',
      'deviceBrand': device.brand ?? _deviceContext.brand,
      'deviceModel': device.model ?? _deviceContext.model,
      'deviceType': _deviceContext.deviceType,
      'devicePixelRatio': system.devicePixelRatio,
      'deviceOrientation':
          system.windowWidth >= system.windowHeight ? 'landscape' : 'portrait',
      'fontSizeSetting': 0,
      'host': '',
      'hostFontSizeSetting': '',
      'hostSDKVersion': '',
      'hostName': '',
      'hostVersion': '',
      'hostLanguage': system.locale,
      'hostTheme': system.brightness,
      'hostPackageName': '',
      'language': system.locale,
      'model': device.model ?? _deviceContext.model,
      'osName': device.systemName ?? platform,
      'osVersion': device.systemVersion ?? '',
      'osLanguage': system.locale,
      'osTheme': system.brightness,
      'pixelRatio': system.devicePixelRatio,
      'screenWidth': system.screenWidth,
      'screenHeight': system.screenHeight,
      'statusBarHeight': system.safeAreaTop,
      'storage': '',
      'swanNativeVersion': '',
      'system': '${device.systemName ?? platform} ${device.systemVersion ?? ''}'
          .trim(),
      'safeArea': safeAreaInsets,
      'safeAreaInsets': safeAreaInsets,
      'ua': device.browser ?? '',
      'uniCompileVersion': '',
      'uniPlatform': platform,
      'uniRuntimeVersion': '',
      'version': _environment.appVersion,
      'romName': '',
      'romVersion': '',
      'windowWidth': system.windowWidth,
      'windowHeight': system.windowHeight,
      'navigationBarHeight': 0,
      'titleBarHeight': 0,
      'appPlatform': platform,
      'windowTop': system.safeAreaTop,
      'windowBottom': system.safeAreaBottom,
      'bluetoothEnabled': network.types.any((item) => item.name == 'bluetooth'),
      'locationEnabled': false,
      'wifiEnabled': network.types.any((item) => item.name == 'wifi'),
      'cacheLocation': '',
      'theme': system.brightness,
      'isEnabled': true,
      'remarks': device.warning ?? '',
    };
  }

  Future<Object?> register({String? name}) async {
    final username = _environment.deviceRegistrationBasicUsername;
    final password = _environment.deviceRegistrationBasicPassword;
    if (username.isEmpty || password.isEmpty) {
      throw StateError('设备注册 Basic 凭据未配置。');
    }
    final basic = base64Encode(utf8.encode('$username:$password'));
    return _apiClient.post<Object?>(
      '/api/chat/device/register',
      data: await collectPayload(name: name),
      headers: <String, String>{'Authorization': 'Basic $basic'},
      // Basic endpoint must neither send a Bearer token nor invoke refresh.
      retryOnUnauthorized: false,
    );
  }
}
