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
import '../data/models/session_summary.dart';
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
    _deviceTypesBySession.clear();
    _sessionIdsByDestination.clear();
    _pendingTypesByDestination.clear();
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

  /// Lets a page bind its existing contact/session rows. Binding does not make
  /// a network request; any pending SignalR update becomes visible at once.
  void bindContacts(Iterable<ContactGroup> groups) {
    _bindSessionDestinations(
      groups.expand(
        (group) => group.contacts.map(
          (contact) => (sessionUnitId: contact.id, raw: contact.raw),
        ),
      ),
    );
  }

  /// Registers currently rendered session rows so the same friend snapshot
  /// can decorate their avatars without another HTTP request.
  void bindSessions(Iterable<SessionSummary> sessions) {
    _bindSessionDestinations(
      sessions.map((session) => (sessionUnitId: session.id, raw: session.raw)),
    );
  }

  void _bindSessionDestinations(
    Iterable<({String sessionUnitId, Map<String, dynamic> raw})> entries,
  ) {
    var changed = false;
    for (final entry in entries) {
      final destinationId = _destinationId(entry.raw);
      if (destinationId == null || entry.sessionUnitId.isEmpty) continue;
      final ids = _sessionIdsByDestination.putIfAbsent(destinationId, () => {});
      if (ids.add(entry.sessionUnitId)) changed = true;
      final pending = _pendingTypesByDestination[destinationId];
      if (pending != null) {
        final previous = _deviceTypesBySession[entry.sessionUnitId];
        final next = pending.toList(growable: false);
        if (!listEquals(previous, next)) {
          _deviceTypesBySession[entry.sessionUnitId] = next;
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
      _activeOwnerId ??= ownerId;
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

  int? _destinationId(Map<String, dynamic> raw) {
    final destination = raw['destination'];
    final value =
        destination is Map
            ? (destination['id'] ?? destination['Id'])
            : (raw['destinationId'] ?? raw['DestinationId']);
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
    return FriendPresenceStore(
      gateway: ref.watch(signalRGatewayProvider),
      sessionRepository: ref.watch(sessionRepositoryProvider),
      contactsApi: ContactsApi(ref.watch(apiClientProvider)),
      minimumRefreshInterval:
          ref.watch(appEnvironmentProvider).friendPresenceRefreshMinInterval,
    );
  },
);
