import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../config/app_environment.dart';
import '../native/native.dart';
import '../platform/platform_contract.dart';
import 'browser_fingerprint.dart';

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
    // The SignalR connection-pool backend accepts these DTO-style aliases.
    'deviceBrand': brand,
    'deviceModel': model,
    'platform': platform,
    'browser': browser,
  };
}

class ClientDeviceContextFactory {
  ClientDeviceContextFactory({
    FlutterSecureStorage? storage,
    Uuid? uuid,
    NativeDevice? nativeDevice,
  }) : _storage =
           storage ??
           const FlutterSecureStorage(
             iOptions: IOSOptions(
               accessibility: KeychainAccessibility.first_unlock,
               synchronizable: false,
             ),
             aOptions: AndroidOptions(resetOnError: true),
           ),
       _uuid = uuid ?? const Uuid(),
       _nativeDevice = nativeDevice ?? Native.device;

  static const _deviceIdKey = 'gotoim.device-id.v1';

  final FlutterSecureStorage _storage;
  final Uuid _uuid;
  final NativeDevice _nativeDevice;

  static String _formatToUuid(String input) {
    final trimmed = input.trim().toLowerCase();
    final uuidPattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    );
    if (uuidPattern.hasMatch(trimmed)) {
      return trimmed;
    }
    final bytes = utf8.encode(trimmed);
    final hex = sha256.convert(bytes).toString();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  Future<String> resolveDeviceId({
    required PlatformFacade platformFacade,
  }) async {
    String? deviceId;
    try {
      deviceId = await _storage.read(key: _deviceIdKey);
      if (deviceId != null && deviceId.trim().isNotEmpty) {
        return _formatToUuid(deviceId.trim());
      }
    } catch (_) {}

    // Resolve hardware or environment permanent identifier
    try {
      if (platformFacade.isWeb) {
        deviceId = await getBrowserFingerprint();
      } else {
        switch (platformFacade.kind) {
          case PlatformKind.android:
          case PlatformKind.ios:
            deviceId = await _nativeDevice.getPermanentDeviceId();
            break;
          case PlatformKind.windows:
            final winInfo = await DeviceInfoPlugin().windowsInfo;
            if (winInfo.deviceId.isNotEmpty) {
              deviceId = _formatToUuid(winInfo.deviceId);
            }
            break;
          case PlatformKind.macos:
            final macInfo = await DeviceInfoPlugin().macOsInfo;
            if (macInfo.systemGUID != null && macInfo.systemGUID!.isNotEmpty) {
              deviceId = _formatToUuid(macInfo.systemGUID!);
            }
            break;
          case PlatformKind.linux:
            final linuxInfo = await DeviceInfoPlugin().linuxInfo;
            if (linuxInfo.machineId != null &&
                linuxInfo.machineId!.isNotEmpty) {
              deviceId = _formatToUuid(linuxInfo.machineId!);
            }
            break;
          default:
            break;
        }
      }
    } catch (_) {}

    if (deviceId == null || deviceId.trim().isEmpty) {
      deviceId = _uuid.v4();
    } else {
      deviceId = _formatToUuid(deviceId);
    }

    try {
      await _storage.write(key: _deviceIdKey, value: deviceId);
    } catch (_) {}

    return deviceId;
  }

  Future<ClientDeviceContext> create({
    required AppEnvironment environment,
    required PlatformFacade platformFacade,
  }) async {
    final deviceId = await resolveDeviceId(platformFacade: platformFacade);
    final kind = platformFacade.kind.name;
    final deviceDetails = await _readDeviceDetails();
    return ClientDeviceContext(
      appId: environment.appId,
      appName: environment.appName,
      appVersion: environment.appVersion,
      deviceId: deviceId,
      deviceType: platformFacade.isWeb ? 'web' : kind,
      platform: kind,
      brand: deviceDetails.brand,
      model: deviceDetails.model,
      browser: deviceDetails.browser,
      pushClientId: '',
    );
  }

  Future<({String brand, String model, String browser})>
  _readDeviceDetails() async {
    try {
      final data = (await DeviceInfoPlugin().deviceInfo).data;
      String value(Iterable<String> keys) {
        for (final key in keys) {
          final raw = data[key]?.toString().trim() ?? '';
          if (raw.isNotEmpty && raw != 'null') return raw;
        }
        return '';
      }

      return (
        brand: value(const <String>[
          'brand',
          'manufacturer',
          'vendor',
          'computerName',
        ]),
        model: value(const <String>['model', 'productName', 'machine', 'name']),
        browser: value(const <String>['browserName', 'userAgent']),
      );
    } catch (_) {
      // Device metadata is supplementary. SignalR must remain connectable on
      // platforms where a native device-info implementation is unavailable.
      return (brand: '', model: '', browser: kIsWeb ? 'web' : '');
    }
  }
}

final clientDeviceContextProvider = Provider<ClientDeviceContext>(
  (ref) {
    final env = ref.watch(appEnvironmentProvider);
    return ClientDeviceContext(
      appId: env.appId,
      appName: env.appName,
      appVersion: env.appVersion,
      deviceId: 'device-subwindow-${const Uuid().v4().substring(0, 8)}',
      deviceType: 'desktop',
      platform: 'windows',
      brand: '',
      model: '',
      browser: '',
      pushClientId: '',
    );
  },
);
