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
  final Map<int, List<LoggedInDevice>> _onlineDevicesByChatObject = {};
  StreamSubscription<SignalRAppEvent>? _subscription;
  DateTime? _lastRefreshAt;
  Future<void>? _refreshing;
  int? _activeOwnerId;

  List<String> deviceTypesForChatObjectId(int? destinationId) =>
      destinationId == null
          ? const <String>[]
          : (_deviceTypesByDestination[destinationId]?.toList(
                growable: false,
              ) ??
              const <String>[]);

  /// Full connection/device details are available for the current chat owner
  /// from `/api/chat/online/by-current-user`, not merely its device types.
  List<LoggedInDevice> onlineDevicesForChatObjectId(int? chatObjectId) =>
      chatObjectId == null
          ? const <LoggedInDevice>[]
          : List<LoggedInDevice>.unmodifiable(
            _onlineDevicesByChatObject[chatObjectId] ??
                const <LoggedInDevice>[],
          );

  void start() {
    _ensureSubscription();
    unawaited(refresh(force: true));
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
    _deviceTypesByDestination.clear();
    _onlineDevicesByChatObject.clear();
    notifyListeners();
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

  void _onSignalREvent(SignalRAppEvent event) {
    if (event is SignalRConnectionEvent &&
        event.state == SignalRConnectionState.connected) {
      unawaited(refresh());
      return;
    }
    if (event is! SignalRCommandEvent) return;
    if (event.command == SignalRCommand.onlineFriend) {
      _applyFriendEvent(event.payload, online: true);
    } else if (event.command == SignalRCommand.offlineFriend) {
      _applyFriendEvent(event.payload, online: false);
    } else if (event.command == SignalRCommand.onlineMe ||
        event.command == SignalRCommand.offlineMe) {
      unawaited(refresh());
    }
  }

  void _applyFriendEvent(Object? payload, {required bool online}) {
    if (payload is! Map) return;
    final data = Map<String, dynamic>.from(payload);
    final rawIds = data['chatObjectIdList'] ?? data['ChatObjectIdList'];
    final rawTypes = data['deviceTypes'] ?? data['DeviceTypes'];
    final destinationIds =
        (rawIds as List? ?? const <Object?>[])
            .map((item) => item is num ? item.toInt() : int.tryParse('$item'))
            .whereType<int>();
    final deviceTypes =
        (rawTypes as List? ?? const <Object?>[])
            .map((item) => '$item')
            .where((item) => item.isNotEmpty)
            .toSet();
    if (deviceTypes.isEmpty) return;
    var changed = false;
    for (final destinationId in destinationIds) {
      final types = _deviceTypesByDestination.putIfAbsent(
        destinationId,
        () => {},
      );
      if (online) {
        final before = types.length;
        types.addAll(deviceTypes);
        changed = types.length != before || changed;
      } else {
        final before = types.length;
        types.removeAll(deviceTypes);
        changed = types.length != before || changed;
      }
    }
    if (changed) notifyListeners();
  }

  Future<void> refresh({bool force = false}) {
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
    final nextByDestination = <int, Set<String>>{};
    for (final item in online) {
      nextByDestination
          .putIfAbsent(item.destinationId, () => {})
          .addAll(item.deviceTypes);
    }
    final ownTypes = currentOwnerDeviceTypes.toSet();
    if (currentOwnerId > 0 && ownTypes.isNotEmpty) {
      nextByDestination.putIfAbsent(currentOwnerId, () => {}).addAll(ownTypes);
    }
    _deviceTypesByDestination
      ..clear()
      ..addAll(nextByDestination);
    _onlineDevicesByChatObject
      ..clear()
      ..[currentOwnerId] = List<LoggedInDevice>.unmodifiable(
        currentOwnerDevices,
      );
    notifyListeners();
  }

  @override
  void dispose() {
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
