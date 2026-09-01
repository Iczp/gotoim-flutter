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
import '../data/session_change_bus.dart';

final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => SessionRepository(
    api: SessionUnitApi(ref.watch(apiClientProvider)),
    dao: SessionDao(ref.watch(unifiedDatabaseProvider)),
    changeBus: ref.watch(sessionChangeBusProvider),
  ),
);

final sessionListControllerProvider =
    ChangeNotifierProvider<SessionListController>(
      (ref) => SessionListController(
        ref.watch(sessionRepositoryProvider),
        ref.watch(signalRGatewayProvider),
        ref.watch(clientDeviceContextProvider),
        ref.watch(sessionChangeBusProvider),
      ),
    );

class SessionListController extends ChangeNotifier {
  SessionListController(
    this._repository,
    this._signalRGateway,
    this._deviceContext,
    this._changeBus,
  ) : _connectionState = _signalRGateway.connectionState {
    _signalSubscription = _signalRGateway.events.listen((event) {
      if (event is SignalRConnectionEvent) {
        _connectionState = event.state;
        notifyListeners();
      } else if (event is SignalRCommandEvent &&
          _shouldSyncForCommand(event.command)) {
        _scheduleRemoteChanges();
      }
    });
    _changeSubscription = _changeBus.events.listen((event) {
      if (event.ownerId == _currentOwner?.id) _scheduleLocalReload();
    });
  }
  static const pageSize = 50;
  final SessionRepository _repository;
  final SignalRGateway _signalRGateway;
  final ClientDeviceContext _deviceContext;
  final SessionChangeBus _changeBus;
  late final StreamSubscription<SignalRAppEvent> _signalSubscription;
  late final StreamSubscription<SessionChangeEvent> _changeSubscription;
  Timer? _localReloadTimer;
  Timer? _remoteChangeTimer;
  final List<SessionSummary> _sessions = [];
  List<ChatOwner> _owners = const [];
  ChatOwner? _currentOwner;
  bool _isLoading = false;
  bool _isRefreshing = false;
  bool _remoteInitialized = false;
  bool _hasMore = true;
  int? _totalCount;
  Object? _error;
  List<LoggedInDevice> _devices = const [];
  bool _isLoadingDevices = false;
  late SignalRConnectionState _connectionState;
  int _focusUnreadRequest = 0;

  List<SessionSummary> get sessions => List.unmodifiable(_sessions);
  List<ChatOwner> get owners => _owners;
  ChatOwner? get currentOwner => _currentOwner;
  bool get isLoading => _isLoading;
  bool get isRefreshing => _isRefreshing;
  bool get isRemoteInitialized => _remoteInitialized;
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
  int get focusUnreadRequest => _focusUnreadRequest;

  void requestFocusUnread() {
    if (!_sessions.any((session) => session.unreadCount > 0)) return;
    _focusUnreadRequest++;
    notifyListeners();
  }

  Future<void> reconnectSignalR() => _signalRGateway.connect();

  /// Loads Drift first, then fetches remote owners and the first friend page.
  /// A failed offline attempt deliberately remains retryable: callers can run
  /// this again after connectivity returns without recreating the controller.
  Future<void> initialize({bool forceRemote = false}) async {
    if (_isLoading || (_remoteInitialized && !forceRemote)) return;
    _isLoading = true;
    _error = null;
    notifyListeners();
    final savedOwnerId = await _repository.readCurrentOwnerId();
    try {
      _owners = await _repository.loadLocalOwners();
      if (_owners.isEmpty && savedOwnerId != null) {
        _owners = <ChatOwner>[
          ChatOwner(
            id: savedOwnerId,
            name: '聊天身份 $savedOwnerId',
            imageUrl: null,
            typeDescription: '',
          ),
        ];
      }
      if (_owners.isNotEmpty) {
        _currentOwner = _ownerById(savedOwnerId) ?? _owners.first;
        final cached = await _repository.loadLocalFriends(
          ownerId: _currentOwner!.id,
          limit: pageSize,
        );
        _sessions
          ..clear()
          ..addAll(cached);
        _hasMore = true;
        debugPrint(
          '[sessionInitialize][local] ownerId=${_currentOwner!.id} '
          'owners=${_owners.length} friends=${cached.length}',
        );
        notifyListeners();
      }

      final remoteOwners = await _repository.loadOwners();
      if (remoteOwners.isEmpty && _currentOwner == null) {
        throw StateError('当前账号没有可用的聊天对象');
      }
      if (remoteOwners.isNotEmpty) {
        final previousOwnerId = _currentOwner?.id;
        _owners = remoteOwners;
        _currentOwner =
            _ownerById(previousOwnerId) ??
            _ownerById(savedOwnerId) ??
            remoteOwners.first;
        await _repository.saveCurrentOwnerId(_currentOwner!.id);
        await _loadNextPageInternal(reset: true);
        _remoteInitialized = true;
      }
      unawaited(loadDevices(silent: true));
    } catch (error) {
      // A cached identity is sufficient to render the identity drawer and an
      // empty (but usable) offline session list. Do not replace it with a
      // blocking error simply because this owner currently has no friends.
      if (_currentOwner == null) {
        _error = error;
      } else {
        debugPrint(
          '[sessionInitialize][remote-failed] keepLocalOwner='
          '${_currentOwner!.id} keepLocalFriends=${_sessions.length} '
          'error=$error',
        );
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  ChatOwner? _ownerById(int? id) {
    if (id == null) return null;
    for (final owner in _owners) {
      if (owner.id == id) return owner;
    }
    return null;
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
    _changeSubscription.cancel();
    _localReloadTimer?.cancel();
    _remoteChangeTimer?.cancel();
    super.dispose();
  }

  bool _shouldSyncForCommand(SignalRCommand command) =>
      command == SignalRCommand.messageCreated ||
      command == SignalRCommand.messageForwarded ||
      command == SignalRCommand.messageUpdated ||
      command == SignalRCommand.messageBadgeUpdated ||
      command == SignalRCommand.messageRollbacked ||
      command == SignalRCommand.sessionUnitChanged;

  void _scheduleLocalReload() {
    _localReloadTimer?.cancel();
    _localReloadTimer = Timer(const Duration(milliseconds: 80), () async {
      final owner = _currentOwner;
      if (owner == null) return;
      final local = await _repository.loadLocalFriends(
        ownerId: owner.id,
        limit: _sessions.length < pageSize ? pageSize : _sessions.length,
      );
      final changed = !listEquals(_sessions, local);
      debugPrint(
        '[SessionScrollTrace] 🔄 _scheduleLocalReload | changed=$changed '
        'previousCount=${_sessions.length} newCount=${local.length}',
      );
      if (changed) {
        _sessions
          ..clear()
          ..addAll(local);
        notifyListeners();
      }
    });
  }

  void _scheduleRemoteChanges() {
    _remoteChangeTimer?.cancel();
    _remoteChangeTimer = Timer(const Duration(milliseconds: 250), () async {
      if (_currentOwner == null || _isRefreshing) return;
      try {
        await refreshChanges();
      } catch (_) {
        // refreshChanges already exposes the error to diagnostics/UI.
      }
    });
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

  Future<void> updateCurrentOwner(ChatOwner owner) async {
    _owners = _owners
        .map((item) => item.id == owner.id ? owner : item)
        .toList(growable: false);
    if (_currentOwner?.id == owner.id) _currentOwner = owner;
    await _repository.saveOwner(owner);
    notifyListeners();
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

  Future<void> reloadVisibleLocal() async {
    final owner = _currentOwner;
    if (owner == null) return;
    final local = await _repository.loadLocalFriends(
      ownerId: owner.id,
      limit: _sessions.length < pageSize ? pageSize : _sessions.length,
    );
    final changed = !listEquals(_sessions, local);
    debugPrint(
      '[SessionScrollTrace] 🔄 reloadVisibleLocal | changed=$changed '
      'previousCount=${_sessions.length} newCount=${local.length}',
    );
    if (changed) {
      _sessions
        ..clear()
        ..addAll(local);
      notifyListeners();
    }
  }

  Future<void> setTopping(SessionSummary session, bool value) async {
    final ownerId = session.ownerId ?? _currentOwner?.id;
    if (ownerId == null) return;
    await _repository.setTopping(
      ownerId: ownerId,
      sessionUnitId: session.id,
      value: value,
    );
  }

  Future<void> setImmersed(SessionSummary session, bool value) async {
    final ownerId = session.ownerId ?? _currentOwner?.id;
    if (ownerId == null) return;
    await _repository.setImmersed(
      ownerId: ownerId,
      sessionUnitId: session.id,
      value: value,
    );
  }

  Future<void> clearMessages(SessionSummary session) async {
    final ownerId = session.ownerId ?? _currentOwner?.id;
    if (ownerId == null) return;
    await _repository.clearMessages(
      ownerId: ownerId,
      sessionUnitId: session.id,
    );
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
