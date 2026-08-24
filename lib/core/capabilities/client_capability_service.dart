import 'dart:async';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:app_settings/app_settings.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/app_environment.dart';
import '../device/client_device_context.dart';
import '../notifications/local_notification_contract.dart';
import '../notifications/local_notification_service.dart';
import '../platform/platform_contract.dart';
import '../services/clipboard_service.dart';
import '../services/file/file_picker_service.dart';
import '../services/media/media_service.dart';
import '../services/media/video_processing_models.dart';
import '../services/scan/scan_code_service.dart';
import 'client_capability_models.dart';

/// The application-facing entry point for client/platform capabilities.
///
/// Feature UI and the H5 bridge use this contract instead of plugin packages.
abstract class ClientCapabilityService {
  Future<ClientSystemInfo> getSystemInfo();

  Future<ClientDeviceInfo> getDeviceInfo();

  Future<ClientNetworkStatus> getNetworkType();

  Future<ClientWifiInfo> getWifiInfo();

  Future<ClientNativeActionResult> requestWifiInfoPermission();

  Future<ClientNativeActionResult> requestPermission(
    ClientPermissionKind permission,
  );

  Future<ClientNativeActionResult> openWifiSettings();

  Future<ClientNativeActionResult> openAppSettings();

  Stream<ClientNetworkStatus> get networkStatusChanges;

  Future<List<ClientCapabilitySupport>> getCapabilities();

  Future<void> setClipboardData(String value);

  Future<String?> getClipboardData();

  Future<List<SelectedFile>> chooseFile(FilePickerRequest request);

  Future<SavedFile?> saveFile(FileSaveRequest request);

  Future<bool> clearTemporaryFiles();

  Future<List<SelectedFile>> chooseImage(MediaPickRequest request);

  Future<SelectedFile?> takePhoto(MediaPickRequest request);

  Future<SelectedFile?> chooseVideo(MediaPickRequest request);

  Future<SelectedFile?> recordVideo(MediaPickRequest request);

  Future<ProcessedImage> compressImage(
    SelectedFile source,
    ImageCompressionRequest request,
  );

  Future<VideoMetadata> getVideoMetadata(SelectedFile source);

  Future<Uint8List> createVideoThumbnail(
    SelectedFile source, {
    int quality,
    int positionMs,
  });

  Future<SelectedFile?> compressVideo(
    SelectedFile source, {
    VideoCompressionQuality quality = VideoCompressionQuality.medium,
    bool includeAudio = true,
  });

  Future<void> startAudioRecording(AudioRecordingRequest request);

  Future<void> pauseAudioRecording();

  Future<void> resumeAudioRecording();

  Future<SelectedFile?> stopAudioRecording();

  Future<void> cancelAudioRecording();

  Future<ScanCodeResult?> scanCode(
    NavigatorState navigator,
    ScanCodeRequest request,
  );

  Future<ScanCodeResult?> decodeImage(DecodeImageRequest request);

  Future<ScanCodeResult?> decodeImageFile(
    SelectedFile file, {
    List<ScanCodeFormat> formats,
  });

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
    required MediaService mediaService,
    required LocalNotificationService localNotificationService,
    Connectivity? connectivity,
    DeviceInfoPlugin? deviceInfoPlugin,
    NetworkInfo? networkInfo,
  }) : _environment = environment,
       _deviceContext = deviceContext,
       _platformFacade = platformFacade,
       _clipboardService = clipboardService,
       _filePickerService = filePickerService,
       _scanCodeService = scanCodeService,
       _imageCodeService = imageCodeService,
       _mediaService = mediaService,
       _localNotificationService = localNotificationService,
       _connectivity = connectivity ?? Connectivity(),
       _deviceInfoPlugin = deviceInfoPlugin ?? DeviceInfoPlugin(),
       _networkInfo = networkInfo ?? NetworkInfo();

  final AppEnvironment _environment;
  final ClientDeviceContext _deviceContext;
  final PlatformFacade _platformFacade;
  final ClipboardService _clipboardService;
  final FilePickerService _filePickerService;
  final ScanCodeService _scanCodeService;
  final ImageCodeService _imageCodeService;
  final MediaService _mediaService;
  final LocalNotificationService _localNotificationService;
  final Connectivity _connectivity;
  final DeviceInfoPlugin _deviceInfoPlugin;
  final NetworkInfo _networkInfo;

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
    try {
      final data = (await _deviceInfoPlugin.deviceInfo).data;
      return _deviceInfoFromData(data);
    } catch (error) {
      // Device plugins can fail on an OEM ROM or before an Android activity is
      // fully attached. System/device APIs must still be usable in that case.
      return ClientDeviceInfo(
        platform: _platformFacade.kind,
        appScopedDeviceId: _deviceContext.deviceId,
        deviceType: _deviceContext.deviceType,
        brand: _deviceContext.brand.isEmpty ? null : _deviceContext.brand,
        model: _deviceContext.model.isEmpty ? null : _deviceContext.model,
        systemName: _platformFacade.kind.name,
        systemVersion: null,
        isPhysicalDevice: null,
        browser: _deviceContext.browser.isEmpty ? null : _deviceContext.browser,
        source: 'fallback',
        warning: '设备插件读取失败，已返回稳定基础信息：$error',
      );
    }
  }

  ClientDeviceInfo _deviceInfoFromData(Map<String, dynamic> data) {
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
      source: 'plugin',
    );
  }

  @override
  Future<ClientNetworkStatus> getNetworkType() async =>
      _networkStatus(await _connectivity.checkConnectivity());

  @override
  Future<ClientWifiInfo> getWifiInfo() async {
    // NetworkInfo exposes a different field set on different Android ROMs and
    // desktop platforms. A missing IPv6/gateway implementation must not hide
    // the SSID or IPv4 result that is still available.
    final values = await Future.wait<String?>(<Future<String?>>[
      _readWifiValue(_networkInfo.getWifiName),
      _readWifiValue(_networkInfo.getWifiBSSID),
      _readWifiValue(_networkInfo.getWifiIP),
      _readWifiValue(_networkInfo.getWifiIPv6),
      _readWifiValue(_networkInfo.getWifiGatewayIP),
      _readWifiValue(_networkInfo.getWifiSubmask),
      _readWifiValue(_networkInfo.getWifiBroadcast),
    ]);
    final info = ClientWifiInfo(
      ssid: _cleanSsid(values[0]),
      bssid: values[1],
      ipAddress: values[2],
      ipv6Address: values[3],
      gatewayIp: values[4],
      submask: values[5],
      broadcast: values[6],
    );
    if (info.ssid != null ||
        info.bssid != null ||
        info.ipAddress != null ||
        info.ipv6Address != null ||
        info.gatewayIp != null ||
        info.submask != null ||
        info.broadcast != null) {
      return info;
    }
    return ClientWifiInfo(
      ssid: null,
      bssid: null,
      ipAddress: null,
      ipv6Address: null,
      gatewayIp: null,
      submask: null,
      broadcast: null,
      warning: '系统暂未提供当前 Wi-Fi 的详细信息。',
    );
  }

  @override
  Future<ClientNativeActionResult> requestWifiInfoPermission() async =>
      const ClientNativeActionResult(
        ok: true,
        status: 'notRequired',
        message: '局域网文件共享不会申请系统定位或 Wi-Fi 运行时权限；SSID 不可用时会留空。',
      );

  @override
  Future<ClientNativeActionResult> requestPermission(
    ClientPermissionKind permission,
  ) async {
    if (permission == ClientPermissionKind.wifiInfo) {
      return requestWifiInfoPermission();
    }
    final nativePermission = switch (permission) {
      ClientPermissionKind.photos => Permission.photos,
      ClientPermissionKind.camera => Permission.camera,
      ClientPermissionKind.microphone => Permission.microphone,
      ClientPermissionKind.wifiInfo => throw StateError('unreachable'),
    };
    try {
      final status = await nativePermission.request();
      final granted = status.isGranted || status.isLimited;
      return ClientNativeActionResult(
        ok: granted,
        status: status.name,
        shouldOpenSettings: _shouldOpenSettings(status),
        message:
            granted
                ? '${_permissionLabel(permission)}权限已授予。'
                : _shouldOpenSettings(status)
                ? '${_permissionLabel(permission)}权限已被系统永久拒绝，请前往应用设置开启。'
                : '${_permissionLabel(permission)}权限未授予，可以再次请求或前往应用设置开启。',
      );
    } catch (error) {
      return ClientNativeActionResult(
        ok: false,
        status: 'error',
        message: '请求${_permissionLabel(permission)}权限失败：$error',
      );
    }
  }

  @override
  Future<ClientNativeActionResult> openWifiSettings() async {
    if (_platformFacade.kind != PlatformKind.android) {
      return const ClientNativeActionResult(
        ok: false,
        status: 'unsupported',
        message: '当前平台不支持直接打开系统 Wi-Fi 设置。',
      );
    }
    try {
      await AppSettings.openAppSettings(type: AppSettingsType.wifi);
      return const ClientNativeActionResult(
        ok: true,
        message: '已请求打开系统 Wi-Fi 设置。',
      );
    } catch (error) {
      return ClientNativeActionResult(
        ok: false,
        message: '无法打开系统 Wi-Fi 设置：$error',
      );
    }
  }

  @override
  Future<ClientNativeActionResult> openAppSettings() async {
    if (_platformFacade.isWeb) {
      return const ClientNativeActionResult(
        ok: false,
        status: 'unsupported',
        message: '浏览器无法打开应用系统设置。',
      );
    }
    try {
      await AppSettings.openAppSettings(type: AppSettingsType.settings);
      return const ClientNativeActionResult(ok: true, message: '已请求打开应用系统设置。');
    } catch (error) {
      return ClientNativeActionResult(ok: false, message: '无法打开应用系统设置：$error');
    }
  }

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
          name: 'media.chooseImage/chooseVideo/camera/recording',
          isSupported: true,
          message: '相册、相机、图片压缩、录音由统一媒体服务提供。',
        ),
        const ClientCapabilitySupport(
          name: 'network.getNetworkType',
          isSupported: true,
          message: '返回网络传输类型，不验证互联网可达性。',
        ),
        ClientCapabilitySupport(
          name: 'network.getWifiInfo',
          isSupported: !_platformFacade.isWeb,
          message:
              _platformFacade.isWeb
                  ? '浏览器不暴露当前 Wi-Fi SSID。'
                  : '读取当前连接的 Wi-Fi 元数据；字段受系统权限限制。',
        ),
        ClientCapabilitySupport(
          name: 'permission.requestWifiInfo',
          isSupported: true,
          message: '局域网文件共享不依赖运行时权限；SSID 字段会按系统可用性读取。',
        ),
        ClientCapabilitySupport(
          name: 'permission.request',
          isSupported: !_platformFacade.isWeb,
          message: '可请求相册、相机、麦克风与 Wi-Fi 信息权限；永久拒绝时返回设置引导。',
        ),
        ClientCapabilitySupport(
          name: 'system.openWifiSettings',
          isSupported: _platformFacade.kind == PlatformKind.android,
          message: '仅 Android 可直接跳转到系统 Wi-Fi 设置。',
        ),
        ClientCapabilitySupport(
          name: 'system.openAppSettings',
          isSupported: !_platformFacade.isWeb,
          message: '打开当前应用的系统设置，用于恢复被拒绝的权限。',
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
          name: 'file.upload',
          isSupported: _environment.jsBridgeUploadAllowedHosts.isNotEmpty,
          message:
              _environment.jsBridgeUploadAllowedHosts.isEmpty
                  ? '当前环境未配置 JS Bridge 上传主机白名单。'
                  : '由 Flutter 宿主使用文件流上传，并支持进度、取消和事件订阅。',
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
  Future<SavedFile?> saveFile(FileSaveRequest request) =>
      _filePickerService.saveFile(request);

  @override
  Future<bool> clearTemporaryFiles() =>
      _filePickerService.clearTemporaryFiles();

  @override
  Future<List<SelectedFile>> chooseImage(MediaPickRequest request) =>
      _mediaService.chooseImage(request);

  @override
  Future<SelectedFile?> takePhoto(MediaPickRequest request) =>
      _mediaService.takePhoto(request);

  @override
  Future<SelectedFile?> chooseVideo(MediaPickRequest request) =>
      _mediaService.chooseVideo(request);

  @override
  Future<SelectedFile?> recordVideo(MediaPickRequest request) =>
      _mediaService.recordVideo(request);

  @override
  Future<ProcessedImage> compressImage(
    SelectedFile source,
    ImageCompressionRequest request,
  ) => _mediaService.compressImage(source, request);

  @override
  Future<VideoMetadata> getVideoMetadata(SelectedFile source) =>
      _mediaService.getVideoMetadata(source);

  @override
  Future<Uint8List> createVideoThumbnail(
    SelectedFile source, {
    int quality = 80,
    int positionMs = 0,
  }) => _mediaService.createVideoThumbnail(
    source,
    quality: quality,
    positionMs: positionMs,
  );

  @override
  Future<SelectedFile?> compressVideo(
    SelectedFile source, {
    VideoCompressionQuality quality = VideoCompressionQuality.medium,
    bool includeAudio = true,
  }) => _mediaService.compressVideo(
    source,
    quality: quality,
    includeAudio: includeAudio,
  );

  @override
  Future<void> startAudioRecording(AudioRecordingRequest request) =>
      _mediaService.startAudioRecording(request);

  @override
  Future<void> pauseAudioRecording() => _mediaService.pauseAudioRecording();

  @override
  Future<void> resumeAudioRecording() => _mediaService.resumeAudioRecording();

  @override
  Future<SelectedFile?> stopAudioRecording() =>
      _mediaService.stopAudioRecording();

  @override
  Future<void> cancelAudioRecording() => _mediaService.cancelAudioRecording();

  @override
  Future<ScanCodeResult?> scanCode(
    NavigatorState navigator,
    ScanCodeRequest request,
  ) => _scanCodeService.scanCode(navigator, request);

  @override
  Future<ScanCodeResult?> decodeImage(DecodeImageRequest request) =>
      _imageCodeService.decodeImage(request);

  /// Opens the independent image decoder over a selected media/file reference.
  @override
  Future<ScanCodeResult?> decodeImageFile(
    SelectedFile file, {
    List<ScanCodeFormat> formats = const <ScanCodeFormat>[
      ScanCodeFormat.qrCode,
    ],
  }) async => _imageCodeService.decodeImage(
    DecodeImageRequest(bytes: await file.readBytes(), formats: formats),
  );

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

  String? _cleanSsid(String? value) {
    final result = value?.trim().replaceAll('"', '');
    return result == null || result.isEmpty || result == '<unknown ssid>'
        ? null
        : result;
  }

  bool _shouldOpenSettings(PermissionStatus status) =>
      status.isPermanentlyDenied || status.isRestricted;

  String _permissionLabel(ClientPermissionKind permission) =>
      switch (permission) {
        ClientPermissionKind.photos => '相册',
        ClientPermissionKind.camera => '相机',
        ClientPermissionKind.microphone => '麦克风',
        ClientPermissionKind.wifiInfo => 'Wi-Fi 信息',
      };

  Future<String?> _readWifiValue(Future<String?> Function() read) async {
    try {
      return await read();
    } catch (_) {
      return null;
    }
  }
}
