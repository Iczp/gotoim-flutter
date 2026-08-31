import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/device/client_device_context.dart';
import '../../../core/network/secure_token_storage.dart';
import '../../../core/network/client_credentials_token_storage.dart';
import '../../../core/network/token_storage.dart';
import '../../../core/realtime/signalr_gateway.dart';
import '../../../core/realtime/signalr_gateway_factory.dart';
import '../data/openid_connect_auth_repository.dart';
import '../domain/auth_repository.dart';

enum AuthStatus { checking, unauthenticated, authenticated }

class AuthController extends ChangeNotifier {
  AuthController(this._repository, this._signalRGateway) {
    _restore();
  }

  final AuthRepository _repository;
  final SignalRGateway _signalRGateway;
  AuthStatus _status = AuthStatus.checking;
  String? _errorMessage;

  AuthStatus get status => _status;
  String? get errorMessage => _errorMessage;
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
      _connectRealtime();
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
      _connectRealtime();
    } catch (error) {
      _status = AuthStatus.unauthenticated;
      _errorMessage = _displayError(error);
    }
    notifyListeners();
  }

  Future<void> logout() async {
    await _signalRGateway.disconnect();
    await _repository.logout();
    _status = AuthStatus.unauthenticated;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> sessionInvalidated() async {
    await _signalRGateway.disconnect();
    _status = AuthStatus.unauthenticated;
    _errorMessage = '登录已过期，请重新登录。';
    notifyListeners();
  }

  Future<void> _restore() async {
    try {
      // A stored session is valid for offline use. In particular, never turn
      // a slow or unavailable refresh endpoint into a local logout here.
      // [restoreSession] only returns false when there is no usable local
      // session or the authorization server definitively rejects it.
      final hasSession = await _repository.restoreSession();
      _status =
          hasSession ? AuthStatus.authenticated : AuthStatus.unauthenticated;
      if (hasSession) _connectRealtime();
    } catch (_) {
      _status = AuthStatus.unauthenticated;
    }
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
  );
  ref.onDispose(gateway.dispose);
  return gateway;
});

final authControllerProvider = ChangeNotifierProvider<AuthController>((ref) {
  return AuthController(
    ref.watch(authRepositoryProvider),
    ref.watch(signalRGatewayProvider),
  );
});
