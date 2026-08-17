import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/realtime/signalr_gateway.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_repository.dart';

enum ConnectionTestStatus { idle, testing, success, failure }

class ConnectionTestController extends ChangeNotifier {
  ConnectionTestController({
    required AuthRepository authRepository,
    required SignalRGateway signalRGateway,
  })  : _authRepository = authRepository,
        _signalRGateway = signalRGateway,
        _connectionState = signalRGateway.connectionState {
    _subscription = _signalRGateway.events.listen(_onSignalREvent);
  }

  final AuthRepository _authRepository;
  final SignalRGateway _signalRGateway;
  late final StreamSubscription<SignalRAppEvent> _subscription;

  SignalRConnectionState _connectionState;
  ConnectionTestStatus _apiStatus = ConnectionTestStatus.idle;
  ConnectionTestStatus _signalRStatus = ConnectionTestStatus.idle;
  String? _apiResult;
  String? _apiError;
  String? _signalRError;
  String? _latestEvent;

  SignalRConnectionState get connectionState => _connectionState;
  ConnectionTestStatus get apiStatus => _apiStatus;
  ConnectionTestStatus get signalRStatus => _signalRStatus;
  String? get apiResult => _apiResult;
  String? get apiError => _apiError;
  String? get signalRError => _signalRError;
  String? get latestEvent => _latestEvent;

  Future<void> testAuthenticatedApi() async {
    _apiStatus = ConnectionTestStatus.testing;
    _apiError = null;
    notifyListeners();
    try {
      final userInfo = await _authRepository.getUserInfo();
      _apiResult = const JsonEncoder.withIndent('  ').convert(userInfo);
      _apiStatus = ConnectionTestStatus.success;
    } catch (error) {
      _apiStatus = ConnectionTestStatus.failure;
      _apiError = _safeError(error);
    }
    notifyListeners();
  }

  Future<void> reconnectSignalR() async {
    _signalRStatus = ConnectionTestStatus.testing;
    _signalRError = null;
    notifyListeners();
    try {
      await _signalRGateway.disconnect();
      await _signalRGateway.connect();
      _connectionState = _signalRGateway.connectionState;
      _signalRStatus = ConnectionTestStatus.success;
    } catch (error) {
      _connectionState = _signalRGateway.connectionState;
      _signalRStatus = ConnectionTestStatus.failure;
      _signalRError = _safeError(error);
    }
    notifyListeners();
  }

  void _onSignalREvent(SignalRAppEvent event) {
    if (event is SignalRConnectionEvent) {
      _connectionState = event.state;
      if (event.error != null) _signalRError = _safeError(event.error!);
      _latestEvent = '连接状态：${event.state.name}';
    } else if (event is SignalRCommandEvent) {
      // Do not render message payloads here; the test screen must not expose IM content.
      _latestEvent = '收到命令：${event.command.value}';
    } else if (event is SignalRUnknownCommandEvent) {
      _latestEvent = '收到未知命令：${event.command ?? '空'}';
    }
    notifyListeners();
  }

  String _safeError(Object error) => error.toString().replaceAll(
      RegExp(r'Bearer\s+\S+', caseSensitive: false), 'Bearer <redacted>');

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

final connectionTestControllerProvider =
    ChangeNotifierProvider<ConnectionTestController>((ref) {
  return ConnectionTestController(
    authRepository: ref.watch(authRepositoryProvider),
    signalRGateway: ref.watch(signalRGatewayProvider),
  );
});
