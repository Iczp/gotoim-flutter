import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/application_providers.dart';
import '../../../core/network/api_client.dart';
import '../../../core/realtime/signalr_gateway.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_repository.dart';

enum ConnectionTestStatus { idle, testing, success, failure }

class ConnectionTestController extends ChangeNotifier {
  ConnectionTestController({
    required AuthRepository authRepository,
    required SignalRGateway signalRGateway,
    required ApiClient apiClient,
  })  : _authRepository = authRepository,
        _signalRGateway = signalRGateway,
        _apiClient = apiClient,
        _connectionState = signalRGateway.connectionState {
    _subscription = _signalRGateway.events.listen(_onSignalREvent);
  }

  final AuthRepository _authRepository;
  final SignalRGateway _signalRGateway;
  final ApiClient _apiClient;
  late final StreamSubscription<SignalRAppEvent> _subscription;

  SignalRConnectionState _connectionState;
  ConnectionTestStatus _apiStatus = ConnectionTestStatus.idle;
  ConnectionTestStatus _refreshStatus = ConnectionTestStatus.idle;
  ConnectionTestStatus _friendsStatus = ConnectionTestStatus.idle;
  ConnectionTestStatus _messagesStatus = ConnectionTestStatus.idle;
  ConnectionTestStatus _signalRStatus = ConnectionTestStatus.idle;
  String? _apiResult;
  String? _apiError;
  String? _refreshResult;
  String? _refreshError;
  String? _friendsResult;
  String? _friendsError;
  String? _messagesResult;
  String? _messagesError;
  String? _signalRError;
  String? _latestEvent;

  SignalRConnectionState get connectionState => _connectionState;
  ConnectionTestStatus get apiStatus => _apiStatus;
  ConnectionTestStatus get refreshStatus => _refreshStatus;
  ConnectionTestStatus get friendsStatus => _friendsStatus;
  ConnectionTestStatus get messagesStatus => _messagesStatus;
  ConnectionTestStatus get signalRStatus => _signalRStatus;
  String? get apiResult => _apiResult;
  String? get apiError => _apiError;
  String? get refreshResult => _refreshResult;
  String? get refreshError => _refreshError;
  String? get friendsResult => _friendsResult;
  String? get friendsError => _friendsError;
  String? get messagesResult => _messagesResult;
  String? get messagesError => _messagesError;
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

  Future<void> refreshToken() async {
    _refreshStatus = ConnectionTestStatus.testing;
    _refreshError = null;
    notifyListeners();
    try {
      final session = await _authRepository.refreshSession();
      _refreshResult = session.expiresIn == null
          ? '刷新成功：服务端未返回 expires_in。'
          : '刷新成功：access token 有效期 ${session.expiresIn!.inSeconds} 秒。';
      _refreshStatus = ConnectionTestStatus.success;
    } catch (error) {
      _refreshStatus = ConnectionTestStatus.failure;
      _refreshError = _safeError(error);
    }
    notifyListeners();
  }

  Future<void> testFriendsApi(String ownerId) async {
    if (ownerId.isEmpty) {
      _friendsStatus = ConnectionTestStatus.failure;
      _friendsError = '请输入 ownerId。';
      notifyListeners();
      return;
    }
    _friendsStatus = ConnectionTestStatus.testing;
    _friendsError = null;
    notifyListeners();
    try {
      final result = await _apiClient.get<dynamic>(
        '/api/chat/session-unit-cache/friends',
        query: <String, Object?>{
          'ownerId': ownerId,
          'maxResultCount': 100,
        },
      );
      _friendsResult = _summarizeResponse(result, label: '好友列表');
      _friendsStatus = ConnectionTestStatus.success;
    } catch (error) {
      _friendsStatus = ConnectionTestStatus.failure;
      _friendsError = _safeError(error);
    }
    notifyListeners();
  }

  Future<void> testMessagesApi(String sessionUnitId) async {
    if (sessionUnitId.isEmpty) {
      _messagesStatus = ConnectionTestStatus.failure;
      _messagesError = '请输入 sessionUnitId。';
      notifyListeners();
      return;
    }
    _messagesStatus = ConnectionTestStatus.testing;
    _messagesError = null;
    notifyListeners();
    try {
      final result = await _apiClient.get<dynamic>(
        '/api/chat/message/fast',
        query: <String, Object?>{'sessionUnitId': sessionUnitId},
      );
      _messagesResult = _summarizeResponse(result, label: '消息列表');
      _messagesStatus = ConnectionTestStatus.success;
    } catch (error) {
      _messagesStatus = ConnectionTestStatus.failure;
      _messagesError = _safeError(error);
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
      _latestEvent = '收到命令：${event.command.value}';
    } else if (event is SignalRUnknownCommandEvent) {
      _latestEvent = '收到未知命令：${event.command ?? '空'}';
    }
    notifyListeners();
  }

  String _safeError(Object error) => error.toString().replaceAll(
        RegExp(r'Bearer\s+\S+', caseSensitive: false),
        'Bearer <redacted>',
      );

  String _summarizeResponse(Object? result, {required String label}) {
    if (result is Map) {
      final items = result['items'];
      final totalCount = result['totalCount'];
      if (items is List) {
        return '$label请求成功：返回 ${items.length} 条，totalCount: ${totalCount ?? '未知'}。';
      }
      return '$label请求成功：返回字段 ${result.keys.join(', ')}。';
    }
    if (result is List) return '$label请求成功：返回 ${result.length} 条。';
    return '$label请求成功：返回类型 ${result.runtimeType}。';
  }

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
    apiClient: ref.watch(apiClientProvider),
  );
});
