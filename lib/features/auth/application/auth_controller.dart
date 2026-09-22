import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../app/application_providers.dart';
import '../../../core/config/app_environment.dart';
import '../../../core/device/client_device_context.dart';
import '../../../core/network/abp/abp_application_configuration_dto.dart';
import '../../../core/network/abp/abp_configuration_repository.dart';
import '../../../core/network/abp/abp_current_user.dart';
import '../../../core/network/secure_token_storage.dart';
import '../../../core/network/client_credentials_token_storage.dart';
import '../../../core/network/token_storage.dart';
import '../../../core/realtime/signalr_gateway.dart';
import '../../../core/realtime/signalr_gateway_factory.dart';
import '../data/openid_connect_auth_repository.dart';
import '../domain/auth_repository.dart';

enum AuthStatus { checking, unauthenticated, authenticated }

class AuthController extends ChangeNotifier {
  AuthController(
    this._repository,
    this._signalRGateway, {
    AbpConfigurationRepository? abpConfigurationRepository,
  }) : _abpConfigurationRepository = abpConfigurationRepository {
    _restore();
  }

  final AuthRepository _repository;
  final SignalRGateway _signalRGateway;
  final AbpConfigurationRepository? _abpConfigurationRepository;
  AuthStatus _status = AuthStatus.checking;
  String? _errorMessage;
  String? _accountName;
  Map<String, dynamic>? _userInfo;
  AbpCurrentUser? _currentUser;
  AbpApplicationConfigurationDto? _applicationConfiguration;
  DateTime? _lastTokenRefreshedAt;

  AuthStatus get status => _status;
  String? get errorMessage => _errorMessage;
  String? get accountName => _accountName;
  Map<String, dynamic>? get userInfo => _userInfo;
  AbpCurrentUser? get currentUser => _currentUser;
  AbpApplicationConfigurationDto? get applicationConfiguration =>
      _applicationConfiguration;
  DateTime? get lastTokenRefreshedAt => _lastTokenRefreshedAt;
  bool get isBusy => _status == AuthStatus.checking;

  Future<void> login({
    required String username,
    required String password,
  }) async {
    _status = AuthStatus.checking;
    _errorMessage = null;
    notifyListeners();
    try {
      await _repository.login(username: username, password: password);
      _status = AuthStatus.authenticated;
      _accountName = username;
      // 新账号登录成功：先重置账号级 Provider，再连接实时通道。
      _onAccountChanged?.call();
      _connectRealtime();
      await _fetchAbpConfigurationSafely();
    } catch (error) {
      _status = AuthStatus.unauthenticated;
      _errorMessage = _displayError(error);
    }
    notifyListeners();
  }

  Future<void> loginWithScanToken(String scanToken) async {
    _status = AuthStatus.checking;
    _errorMessage = null;
    notifyListeners();
    try {
      await _repository.loginWithScanToken(scanToken);
      _status = AuthStatus.authenticated;
      // 新账号登录成功：先重置账号级 Provider，再连接实时通道。
      _onAccountChanged?.call();
      _connectRealtime();
      await _fetchAbpConfigurationSafely();
    } catch (error) {
      _status = AuthStatus.unauthenticated;
      _errorMessage = _displayError(error);
    }
    notifyListeners();
  }

  Future<void> logout() async {
    await _signalRGateway.disconnect();
    await _repository.logout();
    await _abpConfigurationRepository?.clearCache();
    _status = AuthStatus.unauthenticated;
    _errorMessage = null;
    _accountName = null;
    _userInfo = null;
    _currentUser = null;
    _applicationConfiguration = null;
    _lastTokenRefreshedAt = null;
    _onAccountChanged?.call();
    notifyListeners();
  }

  Future<void> sessionInvalidated() async {
    await _signalRGateway.disconnect();
    await _abpConfigurationRepository?.clearCache();
    _status = AuthStatus.unauthenticated;
    _errorMessage = '登录已过期，请重新登录。';
    _accountName = null;
    _userInfo = null;
    _currentUser = null;
    _applicationConfiguration = null;
    _lastTokenRefreshedAt = null;
    _onAccountChanged?.call();
    notifyListeners();
  }

  /// 账号切换回调：退出、会话失效、新账号登录成功时触发，由 Provider 层注入。
  VoidCallback? _onAccountChanged;

  Future<void> _restore() async {
    final startTime = DateTime.now();
    try {
      // 1. 离线优先：优先载入本地持久化缓存中的应用配置与当前账号
      final cachedConfig =
          await _abpConfigurationRepository?.loadCachedConfiguration();
      if (cachedConfig != null) {
        _applicationConfiguration = cachedConfig;
        _currentUser = cachedConfig.currentUser;
        if (_currentUser != null && _currentUser!.displayName.isNotEmpty) {
          _accountName = _currentUser!.displayName;
        }
      }

      final hasSession = await _repository.restoreSession();

      // 保证启动页品牌体验（至少停留 1.5 秒），避免 20ms 闪退导致用户无法感知科技启动屏与全屏沉浸效果
      final elapsed = DateTime.now().difference(startTime);
      if (elapsed < const Duration(milliseconds: 1500)) {
        await Future<void>.delayed(
          const Duration(milliseconds: 1500) - elapsed,
        );
      }

      _status =
          hasSession ? AuthStatus.authenticated : AuthStatus.unauthenticated;
      if (hasSession) {
        _connectRealtime();
        // 2. 进应用必调用 /api/abp/application-configuration 并缓存，同步设置当前登录人
        unawaited(_fetchAbpConfigurationSafely());
        unawaited(_loadUserInfoSafely());
      }
    } catch (_) {
      final elapsed = DateTime.now().difference(startTime);
      if (elapsed < const Duration(milliseconds: 1500)) {
        await Future<void>.delayed(
          const Duration(milliseconds: 1500) - elapsed,
        );
      }
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  Future<void> _fetchAbpConfigurationSafely() async {
    final repo = _abpConfigurationRepository;
    if (repo == null) return;
    try {
      final config = await repo.fetchAndCacheConfiguration();
      _applicationConfiguration = config;
      _currentUser = config.currentUser;
      if (_currentUser != null && _currentUser!.isAuthenticated) {
        _accountName = _currentUser!.displayName;
      }
      notifyListeners();
    } catch (e) {
      debugPrint(
        '[AuthController] Failed to fetch abp application configuration: $e',
      );
    }
  }

  /// 外部主动刷新应用配置与当前账号
  Future<void> fetchApplicationConfiguration({bool force = false}) async {
    await _fetchAbpConfigurationSafely();
  }

  Future<void> _loadUserInfoSafely() async {
    await fetchUserInfo();
  }

  Future<void> fetchUserInfo({bool force = false}) async {
    try {
      final info = await _repository.getUserInfo();
      _userInfo = info;
      final name =
          info['email']?.toString() ??
          info['unique_name']?.toString() ??
          info['preferred_username']?.toString() ??
          info['name']?.toString();
      if (name != null && name.isNotEmpty) {
        _accountName = name;
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> tryRefreshToken() async {
    await _repository.refreshSession();
    _lastTokenRefreshedAt = DateTime.now();
    await fetchUserInfo(force: true);
    notifyListeners();
  }

  String _displayError(Object error) =>
      error.toString().replaceFirst('ApiException(null, null): ', '');

  void _connectRealtime() {
    // A temporary realtime outage must not invalidate a successful login.
    // Its connection/error event is observable by synchronization services.
    _signalRGateway.connect().catchError((Object _) {});
  }
}

final tokenStorageProvider = Provider<TokenStorage>(
  (ref) => SecureTokenStorage(),
);

final clientCredentialsTokenStorageProvider =
    Provider<ClientCredentialsTokenStorage>(
      (ref) => ClientCredentialsTokenStorage(),
    );

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final environment = ref.watch(appEnvironmentProvider);
  final deviceContext = ref.watch(clientDeviceContextProvider);
  return OpenIdConnectAuthRepository(
    dio: OpenIdConnectAuthRepository.createDio(environment, deviceContext),
    environment: environment,
    tokenStorage: ref.watch(tokenStorageProvider),
    clientCredentialsTokenStorage: ref.watch(
      clientCredentialsTokenStorageProvider,
    ),
    deviceContext: deviceContext,
  );
});

final signalRGatewayProvider = Provider<SignalRGateway>((ref) {
  final gateway = createSignalRGateway(
    environment: ref.watch(appEnvironmentProvider),
    readAccessToken: ref.watch(tokenStorageProvider).readAccessToken,
    deviceContext: ref.watch(clientDeviceContextProvider),
    refreshToken: () async {
      final repo = ref.read(authRepositoryProvider);
      if (repo is OpenIdConnectAuthRepository) {
        await repo.refreshAccessToken();
        return ref.read(tokenStorageProvider).readAccessToken();
      }
      return null;
    },
    onSessionInvalidated: () async {
      await ref.read(authControllerProvider.notifier).logout();
    },
  );
  ref.onDispose(gateway.dispose);
  return gateway;
});

/// 账号切换时需要 invalidate 的回调列表。
///
/// 各账号级 Provider 文件在顶层调用 [registerAccountChangedCallback] 注册自己
/// 的 invalidate 操作，避免 [authControllerProvider] 直接依赖 Session 等上层
/// Provider（否则循环依赖）。
final _accountChangedCallbacks = <void Function(Ref)>[];

/// 注册"账号切换时需要执行的清理操作"。
///
/// 调用时机：在 ProviderScope 初始化前，通常在 bootstrap 或 Provider 文件顶层
/// 的 `_registerOnce` 模式中调用一次即可。
void registerAccountChangedCallback(void Function(Ref) callback) {
  if (!_accountChangedCallbacks.contains(callback)) {
    _accountChangedCallbacks.add(callback);
  }
}

void _runAccountChangedCallbacks(Ref ref) {
  for (final cb in _accountChangedCallbacks) {
    cb(ref);
  }
}

final ChangeNotifierProvider<AuthController> authControllerProvider =
    ChangeNotifierProvider<AuthController>((ref) {
      final controller = AuthController(
        ref.watch(authRepositoryProvider),
        ref.watch(signalRGatewayProvider),
        abpConfigurationRepository: ref.watch(
          abpConfigurationRepositoryProvider,
        ),
      );
      // 账号切换时 invalidate 所有已注册的账号级 Provider，确保新账号获得干净状态。
      controller._onAccountChanged = () => _runAccountChangedCallbacks(ref);
      return controller;
    });
