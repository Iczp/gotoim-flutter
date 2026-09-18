import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../app/application_providers.dart';
import '../../../core/config/app_environment.dart';
import '../../../core/realtime/signalr_gateway.dart';
import '../../auth/application/auth_controller.dart';
import '../../contact/data/datasources/contacts_api.dart';
import '../../contact/data/models/online_friend.dart';
import '../data/models/logged_in_device.dart';
import '../data/repositories/session_repository.dart';
import 'session_list_controller.dart';

/// Global friend presence state shared by contact and session-list avatars.
/// It obtains one startup snapshot and stays current through SignalR events.
class FriendPresenceStore extends ChangeNotifier {
  FriendPresenceStore({
    required SignalRGateway gateway,
    required SessionRepository sessionRepository,
    required ContactsApi contactsApi,
    required Duration minimumRefreshInterval,
  }) : _gateway = gateway,
       _sessionRepository = sessionRepository,
       _contactsApi = contactsApi,
       _minimumRefreshInterval = minimumRefreshInterval;

  final SignalRGateway _gateway;
  final SessionRepository _sessionRepository;
  final ContactsApi _contactsApi;
  final Duration _minimumRefreshInterval;
  final Map<int, Set<String>> _deviceTypesByDestination = {};
  final Map<int, Map<String, int>> _deviceCountsByDestination = {};
  final Map<int, List<LoggedInDevice>> _onlineDevicesByChatObject = {};
  List<LoggedInDevice> _currentOnlineDevices = const [];
  StreamSubscription<SignalRAppEvent>? _subscription;
  DateTime? _lastRefreshAt;
  Future<void>? _refreshing;
  Timer? _meRefreshTimer;
  Timer? _authoritativeSyncTimer;
  int? _activeOwnerId;

  List<String> deviceTypesForChatObjectId(int? destinationId) =>
      destinationId == null
          ? const <String>[]
          : (_deviceTypesByDestination[destinationId]?.toList(
                growable: false,
              ) ??
              const <String>[]);

  /// Returns current user's online devices across the whole account.
  List<LoggedInDevice> get currentOnlineDevices => _currentOnlineDevices;

  /// Full connection/device details are available for the current chat owner
  /// from `/api/chat/online/by-current-user`, not merely its device types.
  List<LoggedInDevice> onlineDevicesForChatObjectId(int? chatObjectId) {
    if (chatObjectId == null) return _currentOnlineDevices;
    final devices = _onlineDevicesByChatObject[chatObjectId];
    if (devices != null && devices.isNotEmpty) {
      return devices;
    }
    return _currentOnlineDevices;
  }

  void start() {
    _ensureSubscription();
    if (_gateway.connectionState == SignalRConnectionState.connected) {
      unawaited(refresh(force: true));
    } else {
      _clearPresence();
    }
  }

  void _ensureSubscription() {
    _subscription ??= _gateway.events.listen(_onSignalREvent);
  }

  /// Activates presence for the currently rendered contact owner's friends.
  /// A response for the old owner is discarded by [_refreshInternal].
  Future<void> activateOwner(int ownerId) {
    _ensureSubscription();
    // Rebuilding Contacts for the same owner must not poll the server again.
    if (_activeOwnerId == ownerId) return _refreshing ?? Future.value();
    final previousOwnerId = _activeOwnerId;
    _activeOwnerId = ownerId;
    _clearPresence();
    if (_gateway.connectionState != SignalRConnectionState.connected) {
      return Future.value();
    }
    final inFlight = _refreshing;
    if (inFlight != null) {
      // Startup may still be resolving the current owner. It is the same
      // owner that Contacts is initializing, so sharing the in-flight request
      // avoids an immediate duplicate online-friends query.
      if (previousOwnerId == null) return inFlight;
      return inFlight.whenComplete(() => refresh(force: true));
    }
    return refresh(force: true);
  }

  void _clearPresence() {
    _authoritativeSyncTimer?.cancel();
    _meRefreshTimer?.cancel();
    final hasData =
        _deviceTypesByDestination.isNotEmpty ||
        _deviceCountsByDestination.isNotEmpty ||
        _onlineDevicesByChatObject.isNotEmpty ||
        _currentOnlineDevices.isNotEmpty;
    _deviceTypesByDestination.clear();
    _deviceCountsByDestination.clear();
    _onlineDevicesByChatObject.clear();
    _currentOnlineDevices = const [];
    _lastRefreshAt = null;
    if (hasData) {
      notifyListeners();
    }
  }

  /// Explicitly clears all online presence data (e.g. on logout).
  void clear() => _clearPresence();

  void _onSignalREvent(SignalRAppEvent event) {
    if (event is SignalRConnectionEvent) {
      if (event.state == SignalRConnectionState.connected) {
        unawaited(refresh(force: true));
      } else {
        _clearPresence();
      }
      return;
    }
    if (event is! SignalRCommandEvent) return;
    if (_gateway.connectionState != SignalRConnectionState.connected) return;
    if (event.command == SignalRCommand.onlineFriend) {
      _applyFriendEvent(event.payload, online: true);
    } else if (event.command == SignalRCommand.offlineFriend) {
      _applyFriendEvent(event.payload, online: false);
    } else if (event.command == SignalRCommand.onlineMe ||
        event.command == SignalRCommand.offlineMe) {
      _scheduleMeRefresh();
    }
  }

  void _scheduleMeRefresh() {
    _meRefreshTimer?.cancel();
    _meRefreshTimer = Timer(const Duration(milliseconds: 150), () {
      unawaited(refresh(force: true));
    });
  }

  void _scheduleAuthoritativeSync() {
    _authoritativeSyncTimer?.cancel();
    _authoritativeSyncTimer = Timer(const Duration(milliseconds: 300), () {
      unawaited(refresh(force: true));
    });
  }

  void _applyFriendEvent(Object? payload, {required bool online}) {
    if (payload is! Map) return;
    final data = Map<String, dynamic>.from(payload);
    final rawIds = data['chatObjectIdList'] ?? data['ChatObjectIdList'];
    final rawTypes = data['deviceTypes'] ?? data['DeviceTypes'];
    final destinationIds =
        (rawIds as List? ?? const <Object?>[])
            .map((item) => item is num ? item.toInt() : int.tryParse('$item'))
            .whereType<int>()
            .toList(growable: false);
    final deviceTypes =
        (rawTypes as List? ?? const <Object?>[])
            .map((item) => '$item')
            .where((item) => item.isNotEmpty)
            .toSet();
    if (deviceTypes.isEmpty || destinationIds.isEmpty) return;

    var changed = false;
    for (final destinationId in destinationIds) {
      final counts = _deviceCountsByDestination.putIfAbsent(
        destinationId,
        () => <String, int>{},
      );
      final types = _deviceTypesByDestination.putIfAbsent(
        destinationId,
        () => <String>{},
      );

      for (final type in deviceTypes) {
        final currentCount = counts[type] ?? (types.contains(type) ? 1 : 0);
        if (online) {
          counts[type] = currentCount + 1;
          if (types.add(type)) {
            changed = true;
          }
        } else {
          final newCount = currentCount - 1;
          if (newCount <= 0) {
            counts.remove(type);
            if (types.remove(type)) {
              changed = true;
            }
          } else {
            counts[type] = newCount;
            // Still has active devices of this type!
          }
        }
      }

      if (types.isEmpty) {
        _deviceTypesByDestination.remove(destinationId);
        _deviceCountsByDestination.remove(destinationId);
      }
    }
    if (changed) notifyListeners();

    // Debounce authoritative refresh from backend to ensure consistent state
    _scheduleAuthoritativeSync();
  }

  Future<void> refresh({bool force = false}) {
    if (_gateway.connectionState != SignalRConnectionState.connected) {
      _clearPresence();
      return Future.value();
    }
    final now = DateTime.now();
    if (!force &&
        _lastRefreshAt != null &&
        now.difference(_lastRefreshAt!) < _minimumRefreshInterval) {
      return Future.value();
    }
    return _refreshing ??= _refreshInternal().whenComplete(
      () => _refreshing = null,
    );
  }

  Future<void> _refreshInternal() async {
    if (_gateway.connectionState != SignalRConnectionState.connected) {
      _clearPresence();
      return;
    }
    try {
      final ownerId =
          _activeOwnerId ?? (await _sessionRepository.resolveCurrentOwner()).id;
      _activeOwnerId ??= ownerId;
      // Start both network requests concurrently. The friend endpoint gives
      // presence only; the current-user endpoint retains complete device data.
      final onlineFuture = _contactsApi.getOnlineFriends(ownerId: ownerId);
      final ownDevicesFuture = _sessionRepository.loadOnlineDevices();
      List<OnlineFriend> online = const <OnlineFriend>[];
      List<LoggedInDevice> ownDevices = const <LoggedInDevice>[];
      try {
        online = await onlineFuture;
      } catch (error) {
        debugPrint('[friendPresence][friends-refresh] failed: $error');
      }
      try {
        ownDevices = await ownDevicesFuture;
      } catch (error) {
        debugPrint('[friendPresence][own-devices-refresh] failed: $error');
      }
      if (_gateway.connectionState != SignalRConnectionState.connected) {
        _clearPresence();
        return;
      }
      final ownDeviceTypes = ownDevices
          .map((device) => device.deviceType)
          .where((type) => type.isNotEmpty);
      // The user may have switched chat objects while Redis was queried.
      if (_activeOwnerId != null && _activeOwnerId != ownerId) return;
      _lastRefreshAt = DateTime.now();
      _replaceSnapshot(
        online,
        currentOwnerId: ownerId,
        currentOwnerDeviceTypes: ownDeviceTypes,
        currentOwnerDevices: ownDevices,
      );
    } catch (error) {
      debugPrint('[friendPresence][refresh] failed: $error');
    }
  }

  void _replaceSnapshot(
    List<OnlineFriend> online, {
    required int currentOwnerId,
    required Iterable<String> currentOwnerDeviceTypes,
    required List<LoggedInDevice> currentOwnerDevices,
  }) {
    final nextCountsByDestination = <int, Map<String, int>>{};
    for (final item in online) {
      final map = nextCountsByDestination.putIfAbsent(
        item.destinationId,
        () => <String, int>{},
      );
      for (final type in item.deviceTypes) {
        if (type.isNotEmpty) {
          map[type] = (map[type] ?? 0) + 1;
        }
      }
    }

    final ownDevices = List<LoggedInDevice>.unmodifiable(currentOwnerDevices);
    _currentOnlineDevices = ownDevices;

    final nextOnlineDevicesByChatObject = <int, List<LoggedInDevice>>{};
    if (currentOwnerId > 0) {
      nextOnlineDevicesByChatObject[currentOwnerId] =
          List<LoggedInDevice>.from(currentOwnerDevices);
    }

    for (final device in currentOwnerDevices) {
      final type = device.deviceType;
      for (final id in device.chatObjectIdList) {
        final list = (nextOnlineDevicesByChatObject[id] ??= <LoggedInDevice>[]);
        if (!list.any((d) => d.connectionId == device.connectionId)) {
          list.add(device);
        }
        if (type.isNotEmpty) {
          final map = nextCountsByDestination.putIfAbsent(
            id,
            () => <String, int>{},
          );
          map[type] = (map[type] ?? 0) + 1;
        }
      }
      if (currentOwnerId > 0 && type.isNotEmpty) {
        final map = nextCountsByDestination.putIfAbsent(
          currentOwnerId,
          () => <String, int>{},
        );
        map[type] = (map[type] ?? 0) + 1;
      }
    }

    for (final type in currentOwnerDeviceTypes) {
      if (currentOwnerId > 0 && type.isNotEmpty) {
        final map = nextCountsByDestination.putIfAbsent(
          currentOwnerId,
          () => <String, int>{},
        );
        if ((map[type] ?? 0) == 0) {
          map[type] = 1;
        }
      }
    }

    final nextByDestination = <int, Set<String>>{};
    for (final entry in nextCountsByDestination.entries) {
      final activeTypes = entry.value.entries
          .where((e) => e.value > 0)
          .map((e) => e.key)
          .toSet();
      if (activeTypes.isNotEmpty) {
        nextByDestination[entry.key] = activeTypes;
      }
    }

    _deviceCountsByDestination
      ..clear()
      ..addAll(nextCountsByDestination);
    _deviceTypesByDestination
      ..clear()
      ..addAll(nextByDestination);
    _onlineDevicesByChatObject
      ..clear()
      ..addAll(
        nextOnlineDevicesByChatObject.map(
          (key, value) =>
              MapEntry(key, List<LoggedInDevice>.unmodifiable(value)),
        ),
      );
    notifyListeners();
  }

  @override
  void dispose() {
    _meRefreshTimer?.cancel();
    _authoritativeSyncTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}

final friendPresenceStoreProvider = ChangeNotifierProvider<FriendPresenceStore>(
  (ref) {
    return FriendPresenceStore(
      gateway: ref.watch(signalRGatewayProvider),
      sessionRepository: ref.watch(sessionRepositoryProvider),
      contactsApi: ContactsApi(ref.watch(apiClientProvider)),
      minimumRefreshInterval:
          ref.watch(appEnvironmentProvider).friendPresenceRefreshMinInterval,
    );
  },
);
