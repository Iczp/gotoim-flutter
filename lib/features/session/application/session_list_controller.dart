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

/// Flag to control printing of [SessionScrollTrace] logs. Defaults to false.
bool enableSessionScrollTrace = false;

/// Prints [SessionScrollTrace] logs when [enableSessionScrollTrace] is true.
void sessionScrollTrace(String message) {
  if (enableSessionScrollTrace) {
    debugPrint('[SessionScrollTrace] $message');
  }
}

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

// 账号切换时重置 session 层 Provider，确保新账号加载干净数据。
// 调用 [ensureSessionInvalidatorRegistered] 一次即可完成注册（通常在 bootstrap 中调用）。
bool _sessionInvalidatorRegistered = false;

void ensureSessionInvalidatorRegistered() {
  if (_sessionInvalidatorRegistered) return;
  _sessionInvalidatorRegistered = true;
  registerAccountChangedCallback((ref) {
    ref.invalidate(sessionListControllerProvider);
    ref.invalidate(sessionRepositoryProvider);
  });
}

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
          (event.command == SignalRCommand.onlineMe ||
              event.command == SignalRCommand.offlineMe)) {
        _scheduleOnlineDevicesReload();
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
  Timer? _onlineDevicesReloadTimer;
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
  List<LoggedInDevice> _onlineDevices = const [];
  bool _isLoadingOnlineDevices = false;
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
  List<LoggedInDevice> get onlineDevices => _onlineDevices;
  String get currentDeviceId => _deviceContext.deviceId;
  String get currentDeviceLabel => [
    _deviceContext.deviceType,
    _deviceContext.brand,
    _deviceContext.model,
  ].where((value) => value.isNotEmpty).join(' · ');
  bool get isLoadingDevices => _isLoadingDevices;
  bool get isLoadingOnlineDevices => _isLoadingOnlineDevices;
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
      unawaited(loadOnlineDevices(silent: true));
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

  Future<void> forceLogoutDevice(LoggedInDevice device) async {
    if (device.connectionId.isEmpty) {
      throw StateError('该在线连接缺少 connectionId，无法强制下线');
    }
    await _repository.abortOnlineConnection(
      connectionId: device.connectionId,
      reason: '用户主动断开连接',
    );
    await loadOnlineDevices(silent: true);
  }

  Future<void> loadOnlineDevices({bool silent = false}) async {
    if (_isLoadingOnlineDevices) return;
    _isLoadingOnlineDevices = true;
    if (!silent) notifyListeners();
    try {
      _onlineDevices = await _repository.loadOnlineDevices();
    } catch (error) {
      debugPrint('Load online devices failed: $error');
    } finally {
      _isLoadingOnlineDevices = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _signalSubscription.cancel();
    _changeSubscription.cancel();
    _localReloadTimer?.cancel();
    _remoteChangeTimer?.cancel();
    _onlineDevicesReloadTimer?.cancel();
    super.dispose();
  }

  void _scheduleOnlineDevicesReload() {
    _onlineDevicesReloadTimer?.cancel();
    _onlineDevicesReloadTimer = Timer(
      const Duration(milliseconds: 200),
      () => unawaited(loadOnlineDevices(silent: true)),
    );
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
      final currentCount = _sessions.length;
      final targetLimit = currentCount < pageSize ? pageSize : currentCount;
      final local = await _repository.loadLocalFriends(
        ownerId: owner.id,
        limit: targetLimit,
      );
      final changed = !listEquals(_sessions, local);
      sessionScrollTrace(
        '🔄 _scheduleLocalReload | changed=$changed '
        'previousCount=${_sessions.length} newCount=${local.length}',
      );
      if (changed) {
        _mergeLocalSessions(local);
        notifyListeners();
      }
    });
  }

  void _mergeLocalSessions(List<SessionSummary> updated) {
    if (updated.isEmpty) return;
    if (_sessions.isEmpty) {
      _sessions.addAll(updated);
      return;
    }
    final updatedMap = <String, SessionSummary>{
      for (final item in updated) item.id: item,
    };
    for (var i = 0; i < _sessions.length; i++) {
      final existing = _sessions[i];
      final fresh = updatedMap.remove(existing.id);
      if (fresh != null) {
        _sessions[i] = fresh;
      }
    }
    if (updatedMap.isNotEmpty) {
      _sessions.addAll(updatedMap.values);
    }
    _sessions.sort((a, b) {
      final score = b.score.compareTo(a.score);
      if (score != 0) return score;
      final ticks = b.ticks.compareTo(a.ticks);
      return ticks != 0 ? ticks : b.id.compareTo(a.id);
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
      final changedItems = await _repository.loadChanges(ownerId: owner.id);
      if (changedItems.isNotEmpty) {
        sessionScrollTrace(
          '🔄 refreshChanges | receivedChanges=${changedItems.length} '
          'currentSessions=${_sessions.length}',
        );
        _mergeLocalSessions(changedItems);
      }
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
    final currentCount = _sessions.length;
    final targetLimit = currentCount < pageSize ? pageSize : currentCount;
    final local = await _repository.loadLocalFriends(
      ownerId: owner.id,
      limit: targetLimit,
    );
    final changed = !listEquals(_sessions, local);
    sessionScrollTrace(
      '🔄 reloadVisibleLocal | changed=$changed '
      'previousCount=${_sessions.length} newCount=${local.length}',
    );
    if (changed) {
      _mergeLocalSessions(local);
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
