import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/widgets.dart';

import '../config/app_environment.dart';
import '../device/client_device_context.dart';
import '../notifications/local_notification_contract.dart';
import '../notifications/local_notification_service.dart';
import '../platform/platform_contract.dart';
import '../services/clipboard_service.dart';
import '../services/file/file_picker_service.dart';
import '../services/scan/scan_code_service.dart';
import 'client_capability_models.dart';

/// The application-facing entry point for client/platform capabilities.
///
/// Feature UI and the H5 bridge use this contract instead of plugin packages.
abstract class ClientCapabilityService {
  Future<ClientSystemInfo> getSystemInfo();

  Future<ClientDeviceInfo> getDeviceInfo();

  Future<ClientNetworkStatus> getNetworkType();

  Stream<ClientNetworkStatus> get networkStatusChanges;

  Future<List<ClientCapabilitySupport>> getCapabilities();

  Future<void> setClipboardData(String value);

  Future<String?> getClipboardData();

  Future<List<SelectedFile>> chooseFile(FilePickerRequest request);

  Future<ScanCodeResult?> scanCode(
    NavigatorState navigator,
    ScanCodeRequest request,
  );

  Future<ScanCodeResult?> decodeImage(DecodeImageRequest request);

  LocalNotificationSupport get notificationSupport;

  Future<LocalNotificationPermissionResult> requestNotificationPermission();
}

class DefaultClientCapabilityService implements ClientCapabilityService {
  DefaultClientCapabilityService({
    required AppEnvironment environment,
    required ClientDeviceContext deviceContext,
    required PlatformFacade platformFacade,
    required ClipboardService clipboardService,
    required FilePickerService filePickerService,
    required ScanCodeService scanCodeService,
    required ImageCodeService imageCodeService,
    required LocalNotificationService localNotificationService,
    Connectivity? connectivity,
    DeviceInfoPlugin? deviceInfoPlugin,
  }) : _environment = environment,
       _deviceContext = deviceContext,
       _platformFacade = platformFacade,
       _clipboardService = clipboardService,
       _filePickerService = filePickerService,
       _scanCodeService = scanCodeService,
       _imageCodeService = imageCodeService,
       _localNotificationService = localNotificationService,
       _connectivity = connectivity ?? Connectivity(),
       _deviceInfoPlugin = deviceInfoPlugin ?? DeviceInfoPlugin();

  final AppEnvironment _environment;
  final ClientDeviceContext _deviceContext;
  final PlatformFacade _platformFacade;
  final ClipboardService _clipboardService;
  final FilePickerService _filePickerService;
  final ScanCodeService _scanCodeService;
  final ImageCodeService _imageCodeService;
  final LocalNotificationService _localNotificationService;
  final Connectivity _connectivity;
  final DeviceInfoPlugin _deviceInfoPlugin;

  @override
  Future<ClientSystemInfo> getSystemInfo() async {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final view = dispatcher.implicitView;
    final ratio = view?.devicePixelRatio ?? 1;
    final physicalSize = view?.physicalSize ?? Size.zero;
    final logicalSize = Size(
      physicalSize.width / ratio,
      physicalSize.height / ratio,
    );
    final safeAreaTop = (view?.padding.top ?? 0) / ratio;
    final safeAreaRight = (view?.padding.right ?? 0) / ratio;
    final safeAreaBottom = (view?.padding.bottom ?? 0) / ratio;
    final safeAreaLeft = (view?.padding.left ?? 0) / ratio;
    return ClientSystemInfo(
      platform: _platformFacade.kind,
      isWeb: _platformFacade.isWeb,
      locale: dispatcher.locale.toLanguageTag(),
      brightness: dispatcher.platformBrightness.name,
      devicePixelRatio: ratio,
      windowWidth: logicalSize.width,
      windowHeight: logicalSize.height,
      screenWidth: logicalSize.width,
      screenHeight: logicalSize.height,
      safeAreaTop: safeAreaTop,
      safeAreaRight: safeAreaRight,
      safeAreaBottom: safeAreaBottom,
      safeAreaLeft: safeAreaLeft,
      appId: _environment.appId,
      appName: _environment.appName,
      appVersion: _environment.appVersion,
    );
  }

  @override
  Future<ClientDeviceInfo> getDeviceInfo() async {
    final data = (await _deviceInfoPlugin.deviceInfo).data;
    return ClientDeviceInfo(
      platform: _platformFacade.kind,
      appScopedDeviceId: _deviceContext.deviceId,
      deviceType: _deviceContext.deviceType,
      brand: _string(data, const <String>['brand', 'manufacturer', 'vendor']),
      model: _string(data, const <String>['model', 'machine', 'computerName']),
      systemName: _string(data, const <String>[
        'systemName',
        'name',
        'operatingSystem',
      ]),
      systemVersion: _string(data, const <String>[
        'systemVersion',
        'version',
        'osVersion',
      ]),
      isPhysicalDevice: _bool(data, 'isPhysicalDevice'),
      browser: _string(data, const <String>['browserName', 'userAgent']),
    );
  }

  @override
  Future<ClientNetworkStatus> getNetworkType() async =>
      _networkStatus(await _connectivity.checkConnectivity());

  @override
  Stream<ClientNetworkStatus> get networkStatusChanges =>
      _connectivity.onConnectivityChanged.map(_networkStatus);

  @override
  Future<List<ClientCapabilitySupport>> getCapabilities() async =>
      <ClientCapabilitySupport>[
        ClientCapabilitySupport(
          name: 'system.getSystemInfo',
          isSupported: true,
          message: '当前 Flutter 运行环境支持。',
        ),
        const ClientCapabilitySupport(
          name: 'device.getDeviceInfo',
          isSupported: true,
          message: '当前平台可读取非敏感设备信息。',
        ),
        const ClientCapabilitySupport(
          name: 'network.getNetworkType',
          isSupported: true,
          message: '返回网络传输类型，不验证互联网可达性。',
        ),
        const ClientCapabilitySupport(
          name: 'clipboard.getData/setData',
          isSupported: true,
          message: '由系统剪贴板服务提供。',
        ),
        const ClientCapabilitySupport(
          name: 'file.chooseFile',
          isSupported: true,
          message: '调用系统文件选择器；返回安全的文件元数据。',
        ),
        ClientCapabilitySupport(
          name: 'scan.scanCode',
          isSupported: true,
          message:
              _platformFacade.kind == PlatformKind.android ||
                      _platformFacade.kind == PlatformKind.ios
                  ? '支持相机扫码、相册识别。'
                  : '不启用相机扫码；支持选择或上传图片解码。',
        ),
        ClientCapabilitySupport(
          name: 'notification.local',
          isSupported: notificationSupport.isSupported,
          message: notificationSupport.message,
        ),
      ];

  @override
  Future<void> setClipboardData(String value) => _clipboardService.copy(value);

  @override
  Future<String?> getClipboardData() => _clipboardService.read();

  @override
  Future<List<SelectedFile>> chooseFile(FilePickerRequest request) =>
      _filePickerService.chooseFile(request);

  @override
  Future<ScanCodeResult?> scanCode(
    NavigatorState navigator,
    ScanCodeRequest request,
  ) => _scanCodeService.scanCode(navigator, request);

  @override
  Future<ScanCodeResult?> decodeImage(DecodeImageRequest request) =>
      _imageCodeService.decodeImage(request);

  @override
  LocalNotificationSupport get notificationSupport =>
      _localNotificationService.support;

  @override
  Future<LocalNotificationPermissionResult> requestNotificationPermission() =>
      _localNotificationService.requestPermission();

  ClientNetworkStatus _networkStatus(List<ConnectivityResult> values) {
    final types = values.map(_networkType).toSet().toList(growable: false);
    return ClientNetworkStatus(types: types, observedAt: DateTime.now());
  }

  ClientNetworkType _networkType(ConnectivityResult value) => switch (value) {
    ConnectivityResult.none => ClientNetworkType.none,
    ConnectivityResult.wifi => ClientNetworkType.wifi,
    ConnectivityResult.mobile => ClientNetworkType.mobile,
    ConnectivityResult.ethernet => ClientNetworkType.ethernet,
    ConnectivityResult.bluetooth => ClientNetworkType.bluetooth,
    ConnectivityResult.vpn => ClientNetworkType.vpn,
    ConnectivityResult.satellite => ClientNetworkType.satellite,
    ConnectivityResult.other => ClientNetworkType.other,
  };

  String? _string(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value != null && '$value'.trim().isNotEmpty) {
        return '$value';
      }
    }
    return null;
  }

  bool? _bool(Map<String, dynamic> data, String key) {
    final value = data[key];
    return value is bool ? value : null;
  }
}
