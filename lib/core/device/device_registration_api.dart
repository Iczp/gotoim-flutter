import 'dart:convert';

import '../capabilities/client_capability_service.dart';
import '../capabilities/client_capability_models.dart';
import '../config/app_environment.dart';
import '../network/api_client.dart';
import 'client_device_context.dart';

/// Registers the current installation with the chat backend using a dedicated
/// client-credentials Bearer token, never the signed-in user's token.
class DeviceRegistrationApi {
  DeviceRegistrationApi({
    required ApiClient apiClient,
    required ClientCapabilityService capabilities,
    required ClientDeviceContext deviceContext,
    required AppEnvironment environment,
    required Future<String> Function() readClientCredentialsToken,
  }) : _apiClient = apiClient,
       _capabilities = capabilities,
       _deviceContext = deviceContext,
       _environment = environment,
       _readClientCredentialsToken = readClientCredentialsToken;

  final ApiClient _apiClient;
  final ClientCapabilityService _capabilities;
  final ClientDeviceContext _deviceContext;
  final AppEnvironment _environment;
  final Future<String> Function() _readClientCredentialsToken;

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
      'top': _toInt(system.safeAreaTop),
      'right': _toInt(system.safeAreaRight),
      'bottom': _toInt(system.safeAreaBottom),
      'left': _toInt(system.safeAreaLeft),
    });
    final platform = _deviceContext.platform;
    final appVersionCode =
        int.tryParse(_environment.appVersion.split('.').first) ?? 0;

    // Keep UniApp-compatible names. Values unavailable to Flutter on a given
    // platform are sent as empty values instead of inventing device metadata.
    return <String, Object?>{
      'name':
          name?.trim().isNotEmpty == true
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
      'devicePixelRatio': _toInt(system.devicePixelRatio),
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
      'pixelRatio': _toInt(system.devicePixelRatio),
      'screenWidth': _toInt(system.screenWidth),
      'screenHeight': _toInt(system.screenHeight),
      'statusBarHeight': _toInt(system.safeAreaTop),
      'storage': '',
      'swanNativeVersion': '',
      'system':
          '${device.systemName ?? platform} ${device.systemVersion ?? ''}'
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
      'windowWidth': _toInt(system.windowWidth),
      'windowHeight': _toInt(system.windowHeight),
      'navigationBarHeight': 0,
      'titleBarHeight': 0,
      'appPlatform': platform,
      'windowTop': _toInt(system.safeAreaTop),
      'windowBottom': _toInt(system.safeAreaBottom),
      'bluetoothEnabled': network.types.any((item) => item.name == 'bluetooth'),
      'locationEnabled': false,
      'wifiEnabled': network.types.any((item) => item.name == 'wifi'),
      'cacheLocation': '',
      'theme': system.brightness,
      'isEnabled': true,
      'remarks': device.warning ?? '',
    };
  }

  /// The ABP DTO declares these metrics as Int32. Flutter exposes logical
  /// pixels as doubles, so send an integer rather than JSON `393.0`.
  int _toInt(double value) => value.round();

  Future<Object?> register({String? name}) async {
    final accessToken = await _readClientCredentialsToken();
    return _apiClient.post<Object?>(
      '/api/chat/device/register',
      data: await collectPayload(name: name),
      headers: <String, String>{'Authorization': 'Bearer $accessToken'},
      // This token is independently managed, so user-token refresh is invalid.
      retryOnUnauthorized: false,
    );
  }
}
