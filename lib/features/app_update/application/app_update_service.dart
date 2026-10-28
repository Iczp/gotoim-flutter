import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../app/application_providers.dart';
import '../../../../core/config/app_environment.dart';
import '../../../../core/device/client_device_context.dart';
import '../../../../core/logging/app_logger.dart';
import '../data/datasources/app_update_api.dart';
import '../data/models/app_version_dto.dart';
import '../presentation/app_update_dialog.dart';
import 'app_update_target.dart';
import 'update_url_launcher_stub.dart'
    if (dart.library.io) 'update_url_launcher_io.dart'
    if (dart.library.js_interop) 'update_url_launcher_web.dart'
    as launcher;

/// Service managing app version checks, upgrades, and download installations.
class AppUpdateService extends ChangeNotifier {
  AppUpdateService({
    required AppUpdateApi api,
    Dio? dio,
    required AppEnvironment environment,
    required ClientDeviceContext deviceContext,
    int? currentVersionCode,
  }) : _api = api,
       _dio = dio ?? Dio(),
       _environment = environment,
       _deviceContext = deviceContext,
       _currentVersionCode = currentVersionCode ?? 0,
       _hasExplicitVersionCode = currentVersionCode != null;

  final AppUpdateApi _api;
  final Dio _dio;
  final AppEnvironment _environment;
  final ClientDeviceContext _deviceContext;
  int _currentVersionCode;
  final bool _hasExplicitVersionCode;

  bool _isChecking = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  AppVersionDto? _latestVersion;
  Object? _lastError;

  bool get isChecking => _isChecking;
  bool get isDownloading => _isDownloading;
  double get downloadProgress => _downloadProgress;
  AppVersionDto? get latestVersion => _latestVersion;
  Object? get lastError => _lastError;

  int get currentVersionCode => _currentVersionCode;
  String get currentVersionName => _environment.appVersion;
  String get appId => _environment.appId;

  String get platformName {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.windows => 'windows',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.linux => 'linux',
      _ => 'unknown',
    };
  }

  /// Checks whether an update is required according to version code.
  bool shouldUpdate(AppVersionDto? latest) {
    if (latest == null) return false;
    return latest.versionCode > _currentVersionCode;
  }

  /// Checks the latest version from server.
  Future<AppVersionDto?> checkUpdate({
    bool silent = false,
    BuildContext? context,
  }) async {
    if (_isChecking) return _latestVersion;
    _isChecking = true;
    _lastError = null;
    notifyListeners();

    try {
      if (!_hasExplicitVersionCode) {
        final package = await PackageInfo.fromPlatform();
        final code = int.tryParse(package.buildNumber);
        if (code == null || code < 0) {
          throw const FormatException('无法读取当前应用版本编码');
        }
        _currentVersionCode = code;
      }
      final latest = await _api.getLatestVersion(
        appId: appId,
        platform: platformName,
        versionCode: _currentVersionCode,
        deviceId: _deviceContext.deviceId,
      );
      _latestVersion = latest;
      final needUpdate = shouldUpdate(latest);

      if (context != null && context.mounted) {
        if (needUpdate && latest != null) {
          await AppUpdateDialog.show(
            context,
            version: latest,
            updateService: this,
          );
        } else if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('当前已是最新版本 (v$currentVersionName)'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
      return latest;
    } catch (error, stackTrace) {
      AppLogger.instance.error(
        '[AppUpdateService] checkUpdate failed',
        category: 'app_update',
        event: 'check_update_failed',
        error: error,
        stackTrace: stackTrace,
      );
      _lastError = error;
      if (!silent && context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('检查更新失败，请检查网络后重试'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return null;
    } finally {
      _isChecking = false;
      notifyListeners();
    }
  }

  /// Downloads supported installers or opens the configured update page.
  Future<void> downloadAndInstall(
    AppVersionDto version, {
    void Function(int received, int total)? onProgress,
  }) async {
    final target = planAppUpdate(version, platform: platformName);
    if (target.action == UpdateAction.openUrl) {
      await launcher.openUpdateUrl(target.url);
      return;
    }
    final url = target.url;
    if (_isDownloading) {
      throw StateError('已有更新下载任务');
    }
    _isDownloading = true;
    _downloadProgress = 0.0;
    notifyListeners();
    try {
      final tempDir = await getTemporaryDirectory();
      final extension = switch (target.action) {
        UpdateAction.installAndroidApk => 'apk',
        UpdateAction.installWindowsExe => 'exe',
        UpdateAction.installWindowsMsi => 'msi',
        UpdateAction.openUrl => throw StateError('不支持的安装包'),
      };
      final savePath =
          '${tempDir.path}/gotoim_update_${version.versionCode}.$extension';
      await _dio.download(
        url.toString(),
        savePath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            _downloadProgress = (received / total).clamp(0.0, 1.0);
            notifyListeners();
          }
          onProgress?.call(received, total);
        },
      );
      if (target.action == UpdateAction.installAndroidApk) {
        final result = await OpenFilex.open(
          savePath,
          type: 'application/vnd.android.package-archive',
        );
        if (result.type != ResultType.done) {
          throw StateError('系统无法打开安装包：${result.message}');
        }
      } else {
        await launcher.launchWindowsInstaller(
          savePath,
          msi: extension == 'msi',
        );
      }
    } finally {
      _isDownloading = false;
      notifyListeners();
    }
  }

  Future<void> openPageUrl(String pageUrl) =>
      launcher.openUpdateUrl(checkedUpdateUrl(pageUrl));
}

final appUpdateServiceProvider = ChangeNotifierProvider<AppUpdateService>((
  ref,
) {
  final apiClient = ref.watch(apiClientProvider);
  final env = ref.watch(appEnvironmentProvider);
  final deviceContext = ref.watch(clientDeviceContextProvider);

  return AppUpdateService(
    api: AppUpdateApi(apiClient, environment: env),
    environment: env,
    deviceContext: deviceContext,
  );
});
