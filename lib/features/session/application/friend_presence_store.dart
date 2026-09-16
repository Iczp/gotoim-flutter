import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../app/application_providers.dart';
import '../../../core/config/app_environment.dart';
import '../../../core/realtime/signalr_gateway.dart';
import '../../auth/application/auth_controller.dart';
import '../../contact/data/datasources/contacts_api.dart';
import '../../contact/data/models/contact_group.dart';
import '../../contact/data/models/online_friend.dart';
import '../data/repositories/session_repository.dart';
import 'session_list_controller.dart';

/// App-wide friend presence state. It exists even when the contacts page has
/// never been opened: startup and SignalR reconnect obtain an authoritative
/// Redis snapshot, while friend events update known contacts immediately.
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
  final Map<String, List<String>> _deviceTypesBySession = {};
  final Map<int, Set<String>> _sessionIdsByDestination = {};
  final Map<int, Set<String>> _pendingTypesByDestination = {};
  StreamSubscription<SignalRAppEvent>? _subscription;
  DateTime? _lastRefreshAt;
  Future<void>? _refreshing;
  int? _activeOwnerId;

  List<String> deviceTypesForSession(String sessionUnitId) =>
      _deviceTypesBySession[sessionUnitId] ?? const <String>[];

  void start() {
    _subscription ??= _gateway.events.listen(_onSignalREvent);
    unawaited(refresh(force: true));
  }

  /// Switches the presence namespace when the user selects another chat
  /// object. A response for the old object is discarded by [_refreshInternal].
  Future<void> activateOwner(int ownerId) {
    if (_activeOwnerId == ownerId) return refresh(force: true);
    _activeOwnerId = ownerId;
    _deviceTypesBySession.clear();
    _sessionIdsByDestination.clear();
    _pendingTypesByDestination.clear();
    notifyListeners();
    final inFlight = _refreshing;
    if (inFlight != null) {
      return inFlight.whenComplete(() => refresh(force: true));
    }
    return refresh(force: true);
  }

  /// Lets a page bind its existing contact/session rows. Binding does not make
  /// a network request; any pending SignalR update becomes visible at once.
  void bindContacts(Iterable<ContactGroup> groups) {
    var changed = false;
    for (final contact in groups.expand((group) => group.contacts)) {
      final destinationId = _destinationId(contact);
      if (destinationId == null || contact.id.isEmpty) continue;
      final ids = _sessionIdsByDestination.putIfAbsent(destinationId, () => {});
      if (ids.add(contact.id)) changed = true;
      final pending = _pendingTypesByDestination[destinationId];
      if (pending != null) {
        final previous = _deviceTypesBySession[contact.id];
        final next = pending.toList(growable: false);
        if (!listEquals(previous, next)) {
          _deviceTypesBySession[contact.id] = next;
          changed = true;
        }
      }
    }
    if (changed) notifyListeners();
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
      final types = _pendingTypesByDestination.putIfAbsent(
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
      for (final sessionId
          in _sessionIdsByDestination[destinationId] ?? const <String>{}) {
        final next = types.toList(growable: false);
        if (!listEquals(_deviceTypesBySession[sessionId], next)) {
          _deviceTypesBySession[sessionId] = next;
          changed = true;
        }
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
      final online = await _contactsApi.getOnlineFriends(ownerId: ownerId);
      // The user may have switched chat objects while Redis was queried.
      if (_activeOwnerId != null && _activeOwnerId != ownerId) return;
      _lastRefreshAt = DateTime.now();
      _replaceSnapshot(online);
    } catch (error) {
      debugPrint('[friendPresence][refresh] failed: $error');
    }
  }

  void _replaceSnapshot(List<OnlineFriend> online) {
    final nextByDestination = <int, Set<String>>{};
    final nextBySession = <String, List<String>>{};
    for (final item in online) {
      nextByDestination
          .putIfAbsent(item.destinationId, () => {})
          .addAll(item.deviceTypes);
      nextBySession[item.sessionUnitId] = item.deviceTypes;
      _sessionIdsByDestination
          .putIfAbsent(item.destinationId, () => {})
          .add(item.sessionUnitId);
    }
    _pendingTypesByDestination
      ..clear()
      ..addAll(nextByDestination);
    _deviceTypesBySession
      ..clear()
      ..addAll(nextBySession);
    notifyListeners();
  }

  int? _destinationId(ContactEntry contact) {
    final destination = contact.raw['destination'];
    final value =
        destination is Map
            ? (destination['id'] ?? destination['Id'])
            : (contact.raw['destinationId'] ?? contact.raw['DestinationId']);
    return value is num ? value.toInt() : int.tryParse('$value');
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

final friendPresenceStoreProvider = ChangeNotifierProvider<FriendPresenceStore>(
  (ref) {
    final store = FriendPresenceStore(
      gateway: ref.watch(signalRGatewayProvider),
      sessionRepository: ref.watch(sessionRepositoryProvider),
      contactsApi: ContactsApi(ref.watch(apiClientProvider)),
      minimumRefreshInterval:
          ref.watch(appEnvironmentProvider).friendPresenceRefreshMinInterval,
    );
    ref.onDispose(store.dispose);
    return store;
  },
);
