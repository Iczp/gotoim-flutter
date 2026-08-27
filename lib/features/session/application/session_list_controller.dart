import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../app/application_providers.dart';
import '../../../core/device/client_device_context.dart';
import '../../../core/realtime/signalr_gateway.dart';
import '../../auth/application/auth_controller.dart';
import '../data/datasources/session_dao.dart';
import '../data/datasources/session_unit_api.dart';
import '../data/models/chat_owner.dart';
import '../data/models/session_summary.dart';
import '../data/models/logged_in_device.dart';
import '../data/repositories/session_repository.dart';

final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => SessionRepository(
    api: SessionUnitApi(ref.watch(apiClientProvider)),
    dao: SessionDao(ref.watch(unifiedDatabaseProvider)),
  ),
);

final sessionListControllerProvider =
    ChangeNotifierProvider<SessionListController>(
      (ref) => SessionListController(
        ref.watch(sessionRepositoryProvider),
        ref.watch(signalRGatewayProvider),
        ref.watch(clientDeviceContextProvider),
      ),
    );

class SessionListController extends ChangeNotifier {
  SessionListController(
    this._repository,
    this._signalRGateway,
    this._deviceContext,
  ) : _connectionState = _signalRGateway.connectionState {
    _signalSubscription = _signalRGateway.events.listen((event) {
      if (event is SignalRConnectionEvent) {
        _connectionState = event.state;
        notifyListeners();
      }
    });
  }
  static const pageSize = 50;
  final SessionRepository _repository;
  final SignalRGateway _signalRGateway;
  final ClientDeviceContext _deviceContext;
  late final StreamSubscription<SignalRAppEvent> _signalSubscription;
  final List<SessionSummary> _sessions = [];
  List<ChatOwner> _owners = const [];
  ChatOwner? _currentOwner;
  bool _isLoading = false;
  bool _isRefreshing = false;
  bool _hasMore = true;
  int? _totalCount;
  Object? _error;
  List<LoggedInDevice> _devices = const [];
  bool _isLoadingDevices = false;
  late SignalRConnectionState _connectionState;

  List<SessionSummary> get sessions => List.unmodifiable(_sessions);
  List<ChatOwner> get owners => _owners;
  ChatOwner? get currentOwner => _currentOwner;
  bool get isLoading => _isLoading;
  bool get isRefreshing => _isRefreshing;
  bool get hasMore => _hasMore;
  int? get totalCount => _totalCount;
  Object? get error => _error;
  List<LoggedInDevice> get devices => _devices;
  String get currentDeviceId => _deviceContext.deviceId;
  String get currentDeviceLabel => [
    _deviceContext.deviceType,
    _deviceContext.brand,
    _deviceContext.model,
  ].where((value) => value.isNotEmpty).join(' · ');
  bool get isLoadingDevices => _isLoadingDevices;
  SessionRealtimeStatus get connectionState => switch (_connectionState) {
    SignalRConnectionState.disconnected => SessionRealtimeStatus.disconnected,
    SignalRConnectionState.connecting => SessionRealtimeStatus.connecting,
    SignalRConnectionState.connected => SessionRealtimeStatus.connected,
    SignalRConnectionState.reconnecting => SessionRealtimeStatus.reconnecting,
    SignalRConnectionState.disconnecting => SessionRealtimeStatus.disconnecting,
  };

  Future<void> reconnectSignalR() => _signalRGateway.connect();

  Future<void> initialize() async {
    if (_isLoading || _currentOwner != null) return;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _owners = await _repository.loadOwners();
      if (_owners.isEmpty) throw StateError('当前账号没有可用的聊天对象');
      final savedOwnerId = await _repository.readCurrentOwnerId();
      _currentOwner = _owners.cast<ChatOwner?>().firstWhere(
        (owner) => owner?.id == savedOwnerId,
        orElse: () => _owners.first,
      );
      await _repository.saveCurrentOwnerId(_currentOwner!.id);
      unawaited(loadDevices(silent: true));
      await _loadNextPageInternal(reset: true);
    } catch (error) {
      _error = error;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadDevices({bool silent = false}) async {
    if (_isLoadingDevices) return;
    _isLoadingDevices = true;
    if (!silent) notifyListeners();
    try {
      final devices = await _repository.loadDevices();
      _devices = [...devices]..sort(
        (a, b) =>
            a.deviceId == _deviceContext.deviceId
                ? -1
                : b.deviceId == _deviceContext.deviceId
                ? 1
                : 0,
      );
    } catch (error) {
      debugPrint('Load login devices failed: $error');
    } finally {
      _isLoadingDevices = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _signalSubscription.cancel();
    super.dispose();
  }

  Future<void> selectOwner(ChatOwner owner) async {
    if (_currentOwner?.id == owner.id) return;
    _currentOwner = owner;
    await _repository.saveCurrentOwnerId(owner.id);
    _sessions.clear();
    _hasMore = true;
    _totalCount = null;
    _error = null;
    notifyListeners();
    await loadNextPage();
  }

  Future<void> loadNextPage() async {
    if (_isLoading || !_hasMore || _currentOwner == null) return;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _loadNextPageInternal();
    } catch (error) {
      _error = error;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshChanges() async {
    final owner = _currentOwner;
    if (_isRefreshing || owner == null) return;
    _isRefreshing = true;
    _error = null;
    notifyListeners();
    try {
      await _repository.loadChanges(ownerId: owner.id);
      final local = await _repository.loadLocalFriends(
        ownerId: owner.id,
        limit: pageSize,
      );
      _sessions
        ..clear()
        ..addAll(local);
    } catch (error) {
      _error = error;
      rethrow;
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }

  Future<void> _loadNextPageInternal({bool reset = false}) async {
    final owner = _currentOwner!;
    final last = !reset && _sessions.isNotEmpty ? _sessions.last : null;
    final result = await _repository.loadFriends(
      ownerId: owner.id,
      cursor:
          last == null
              ? null
              : SessionCursor(
                id: last.id,
                score: last.score,
                maxMessageId: last.lastMessageId,
              ),
      limit: pageSize,
    );
    if (reset) _sessions.clear();
    final known = _sessions.map((item) => item.id).toSet();
    _sessions.addAll(result.items.where((item) => known.add(item.id)));
    _hasMore = result.hasMore;
    if (result.totalCount != null) {
      _totalCount = result.totalCount;
    }
  }
}

enum SessionRealtimeStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
  disconnecting,
}
