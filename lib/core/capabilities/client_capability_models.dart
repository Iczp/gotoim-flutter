import '../platform/platform_contract.dart';

enum ClientNetworkType {
  none,
  wifi,
  mobile,
  ethernet,
  bluetooth,
  vpn,
  satellite,
  other,
}

class ClientSystemInfo {
  const ClientSystemInfo({
    required this.platform,
    required this.isWeb,
    required this.locale,
    required this.brightness,
    required this.devicePixelRatio,
    required this.windowWidth,
    required this.windowHeight,
    required this.screenWidth,
    required this.screenHeight,
    required this.safeAreaTop,
    required this.safeAreaRight,
    required this.safeAreaBottom,
    required this.safeAreaLeft,
    required this.appId,
    required this.appName,
    required this.appVersion,
  });

  final PlatformKind platform;
  final bool isWeb;
  final String locale;
  final String brightness;
  final double devicePixelRatio;
  final double windowWidth;
  final double windowHeight;
  final double screenWidth;
  final double screenHeight;
  final double safeAreaTop;
  final double safeAreaRight;
  final double safeAreaBottom;
  final double safeAreaLeft;
  final String appId;
  final String appName;
  final String appVersion;

  Map<String, Object> toJson() => <String, Object>{
    'platform': platform.name,
    'isWeb': isWeb,
    'locale': locale,
    'brightness': brightness,
    'devicePixelRatio': devicePixelRatio,
    'windowWidth': windowWidth,
    'windowHeight': windowHeight,
    'screenWidth': screenWidth,
    'screenHeight': screenHeight,
    'safeAreaInsets': <String, double>{
      'top': safeAreaTop,
      'right': safeAreaRight,
      'bottom': safeAreaBottom,
      'left': safeAreaLeft,
    },
    'appId': appId,
    'appName': appName,
    'appVersion': appVersion,
  };
}

class ClientDeviceInfo {
  const ClientDeviceInfo({
    required this.platform,
    required this.appScopedDeviceId,
    required this.deviceType,
    required this.brand,
    required this.model,
    required this.systemName,
    required this.systemVersion,
    required this.isPhysicalDevice,
    required this.browser,
  });

  final PlatformKind platform;
  final String appScopedDeviceId;
  final String deviceType;
  final String? brand;
  final String? model;
  final String? systemName;
  final String? systemVersion;
  final bool? isPhysicalDevice;
  final String? browser;

  Map<String, Object?> toJson() => <String, Object?>{
    'platform': platform.name,
    'deviceId': appScopedDeviceId,
    'deviceType': deviceType,
    'brand': brand,
    'model': model,
    'systemName': systemName,
    'systemVersion': systemVersion,
    'isPhysicalDevice': isPhysicalDevice,
    'browser': browser,
  };
}

class ClientNetworkStatus {
  const ClientNetworkStatus({required this.types, required this.observedAt});

  final List<ClientNetworkType> types;
  final DateTime observedAt;

  bool get isConnected => !types.contains(ClientNetworkType.none);

  Map<String, Object> toJson() => <String, Object>{
    'networkTypes': types.map((item) => item.name).toList(growable: false),
    'isConnected': isConnected,
    'observedAt': observedAt.toUtc().toIso8601String(),
  };
}

class ClientCapabilitySupport {
  const ClientCapabilitySupport({
    required this.name,
    required this.isSupported,
    required this.message,
  });

  final String name;
  final bool isSupported;
  final String message;

  Map<String, Object> toJson() => <String, Object>{
    'name': name,
    'isSupported': isSupported,
    'message': message,
  };
}
