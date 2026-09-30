import 'dart:io' show Platform;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

/// 统计设备信息
class StatisticDeviceInfo {
  const StatisticDeviceInfo({
    required this.appId,
    required this.deviceKey,
    this.platform,
    this.manufacturer,
    this.model,
    this.osName,
    this.osVersion,
    this.appVersion,
    this.channel,
    this.language,
    this.timeZone,
    this.extraPropertiesJson,
  });

  final String appId;
  final String deviceKey;
  final String? platform;
  final String? manufacturer;
  final String? model;
  final String? osName;
  final String? osVersion;
  final String? appVersion;
  final String? channel;
  final String? language;
  final String? timeZone;
  final String? extraPropertiesJson;

  /// 转换为后端 DeviceInfoDto 请求格式
  Map<String, dynamic> toApiDto() {
    return <String, dynamic>{
      'appId': appId,
      'deviceKey': deviceKey,
      'platform': platform,
      'manufacturer': manufacturer,
      'model': model,
      'osName': osName,
      'osVersion': osVersion,
      'appVersion': appVersion,
      'channel': channel,
      'language': language,
      'timeZone': timeZone,
      'extraPropertiesJson': extraPropertiesJson,
    };
  }

  @override
  String toString() {
    return 'StatisticDeviceInfo(appId: $appId, deviceKey: $deviceKey, platform: $platform, os: $osName $osVersion, appVer: $appVersion)';
  }
}

/// 采集设备信息并管理持久化 DeviceKey
class StatisticDeviceManager {
  StatisticDeviceManager({
    FlutterSecureStorage? storage,
    DeviceInfoPlugin? deviceInfo,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  static const _deviceKeyStorageKey = 'gotoim.statistic.device_key.v1';

  final FlutterSecureStorage _storage;
  final DeviceInfoPlugin _deviceInfo;

  String? _cachedDeviceKey;
  StatisticDeviceInfo? _cachedDeviceInfo;

  StatisticDeviceInfo? get currentDeviceInfo => _cachedDeviceInfo;
  String? get currentDeviceKey => _cachedDeviceKey;

  /// 读取或生成唯一的持久化 DeviceKey
  Future<String> getOrGenerateDeviceKey() async {
    if (_cachedDeviceKey != null) return _cachedDeviceKey!;

    String? key;
    try {
      key = await _storage.read(key: _deviceKeyStorageKey);
      if (key == null || key.isEmpty) {
        key = const Uuid().v4();
        await _storage.write(key: _deviceKeyStorageKey, value: key);
      }
    } catch (_) {
      key ??= const Uuid().v4();
    }
    _cachedDeviceKey = key;
    return key;
  }

  /// 收集当前完整的设备信息
  Future<StatisticDeviceInfo> collectDeviceInfo({
    required String appId,
    required String channel,
    String? fallbackAppVersion,
  }) async {
    final deviceKey = await getOrGenerateDeviceKey();

    String platformName = 'unknown';
    String? manufacturer;
    String? model;
    String? osName;
    String? osVersion;
    String? appVersion = fallbackAppVersion;

    // 1. 读取 PackageInfo
    try {
      final pkg = await PackageInfo.fromPlatform();
      appVersion = pkg.version;
    } catch (_) {}

    // 2. 收集系统与设备详情
    try {
      if (kIsWeb) {
        platformName = 'web';
        final web = await _deviceInfo.webBrowserInfo;
        manufacturer = web.vendor;
        model = web.browserName.name;
        osName = web.platform;
        osVersion = web.userAgent;
      } else if (Platform.isAndroid) {
        platformName = 'android';
        final android = await _deviceInfo.androidInfo;
        manufacturer = android.manufacturer;
        model = android.model;
        osName = 'Android';
        osVersion = android.version.release;
      } else if (Platform.isIOS) {
        platformName = 'ios';
        final ios = await _deviceInfo.iosInfo;
        manufacturer = 'Apple';
        model = ios.utsname.machine;
        osName = ios.systemName;
        osVersion = ios.systemVersion;
      } else if (Platform.isWindows) {
        platformName = 'windows';
        final win = await _deviceInfo.windowsInfo;
        manufacturer = 'Microsoft';
        model = win.computerName;
        osName = 'Windows';
        osVersion = '${win.majorVersion}.${win.minorVersion}';
      } else if (Platform.isMacOS) {
        platformName = 'macos';
        final mac = await _deviceInfo.macOsInfo;
        manufacturer = 'Apple';
        model = mac.model;
        osName = 'macOS';
        osVersion = '${mac.majorVersion}.${mac.minorVersion}';
      } else if (Platform.isLinux) {
        platformName = 'linux';
        final linux = await _deviceInfo.linuxInfo;
        manufacturer = linux.id;
        model = linux.name;
        osName = 'Linux';
        osVersion = linux.versionId;
      }
    } catch (_) {
      // 容错降级
      if (kIsWeb) {
        platformName = 'web';
      } else {
        platformName = Platform.operatingSystem;
      }
    }

    final info = StatisticDeviceInfo(
      appId: appId,
      deviceKey: deviceKey,
      platform: platformName,
      manufacturer: manufacturer,
      model: model,
      osName: osName,
      osVersion: osVersion,
      appVersion: appVersion,
      channel: channel,
      language: PlatformDispatcher.instance.locale.toLanguageTag(),
      timeZone: DateTime.now().timeZoneName,
    );

    _cachedDeviceInfo = info;
    return info;
  }
}
