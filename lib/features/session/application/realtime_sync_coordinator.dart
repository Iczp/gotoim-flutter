import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/realtime/signalr_gateway.dart';
import '../../auth/application/auth_controller.dart';
import '../../chat/application/chat_controller.dart';
import '../../chat/data/repositories/message_repository.dart';
import 'session_list_controller.dart';
import '../data/repositories/session_repository.dart';

/// The sole application-level consumer that turns realtime notifications into
/// persisted IM state. Pages observe repository change buses instead of the
/// SignalR transport, so a closed chat cannot miss an incoming message.
class RealtimeSyncCoordinator {
  RealtimeSyncCoordinator({
    required SignalRGateway gateway,
    required SessionRepository sessionRepository,
    required MessageRepository messageRepository,
    required Future<void> Function(String reason) onKicked,
  }) : _gateway = gateway,
       _sessionRepository = sessionRepository,
       _messageRepository = messageRepository,
       _onKicked = onKicked;

  final SignalRGateway _gateway;
  final SessionRepository _sessionRepository;
  final MessageRepository _messageRepository;
  final Future<void> Function(String reason) _onKicked;
  StreamSubscription<SignalRAppEvent>? _subscription;
  Timer? _syncTimer;
  final Set<int> _pendingOwnerIds = <int>{};
  final Map<int, Future<void>> _syncInFlightByOwner = <int, Future<void>>{};

  void start() {
    _subscription ??= _gateway.events.listen(_onEvent);
  }

  void _onEvent(SignalRAppEvent event) {
    if (event is SignalRConnectionEvent &&
        event.state == SignalRConnectionState.connected) {
      _scheduleCurrentOwnerSync();
      return;
    }
    if (event is! SignalRCommandEvent) return;
    switch (event.command) {
      case SignalRCommand.kicked:
        final payload = event.payload;
        final reason =
            payload is Map
                ? (payload['reason'] ?? payload['Reason'] ?? '未知原因').toString()
                : '未知原因';
        unawaited(_onKicked(reason));
        break;
      case SignalRCommand.messageCreated:
      case SignalRCommand.messageForwarded:
      case SignalRCommand.messageUpdated:
      case SignalRCommand.messageRollbacked:
        unawaited(_handleRealtimeMessage(event));
        break;
      case SignalRCommand.messageBadgeUpdated:
      case SignalRCommand.sessionUnitChanged:
        unawaited(_scheduleTargetedSync(event));
        break;
      default:
        break;
    }
  }

  Future<void> _handleRealtimeMessage(SignalRCommandEvent event) async {
    try {
      final message = await _messageRepository
          .applyRealtimePayloadFromCachedSession(event.payload);
      if (message != null) {
        _scheduleOwnerSync(message.ownerId);
      } else {
        _scheduleCurrentOwnerSync();
      }
    } catch (error) {
      debugPrint('[realtimeSync][message-failed] error=$error');
    }
  }

  Future<void> _scheduleTargetedSync(SignalRCommandEvent event) async {
    final directOwnerId = _extractOwnerId(event.payload);
    if (directOwnerId != null && directOwnerId > 0) {
      _scheduleOwnerSync(directOwnerId);
      return;
    }
    final sessionUnitId = _extractSessionUnitId(event.payload);
    if (sessionUnitId != null && sessionUnitId.isNotEmpty) {
      final friend = await _sessionRepository.loadLocalFriendDetail(
        sessionUnitId,
      );
      if (friend != null && friend.ownerId != null && friend.ownerId! > 0) {
        _scheduleOwnerSync(friend.ownerId!);
        return;
      }
    }
    _scheduleCurrentOwnerSync();
  }

  int? _extractOwnerId(Object? payload) {
    if (payload is! Map) return null;
    final map = Map<String, dynamic>.from(payload);
    final raw = map['ownerId'] ?? map['OwnerId'];
    if (raw is num) return raw.toInt();
    if (raw is String) {
      final parsed = int.tryParse(raw);
      if (parsed != null) return parsed;
    }
    final owner = map['owner'];
    if (owner is Map) {
      final ownerMap = Map<String, dynamic>.from(owner);
      final rawOwnerId = ownerMap['id'] ?? ownerMap['Id'];
      if (rawOwnerId is num) return rawOwnerId.toInt();
      if (rawOwnerId is String) {
        final parsed = int.tryParse(rawOwnerId);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  String? _extractSessionUnitId(Object? payload) {
    if (payload is! Map) return null;
    final map = Map<String, dynamic>.from(payload);
    final raw =
        map['sessionUnitId'] ?? map['SessionUnitId'] ?? map['id'] ?? map['Id'];
    if (raw != null) return '$raw';
    final unit = map['sessionUnit'];
    if (unit is Map) {
      final unitMap = Map<String, dynamic>.from(unit);
      final rawId = unitMap['id'] ?? unitMap['Id'];
      if (rawId != null) return '$rawId';
    }
    return null;
  }

  void _scheduleCurrentOwnerSync() {
    unawaited(() async {
      final currentOwnerId = await _sessionRepository.readCurrentOwnerId();
      if (currentOwnerId != null && currentOwnerId > 0) {
        _scheduleOwnerSync(currentOwnerId);
      }
    }());
  }

  void _scheduleOwnerSync(int ownerId) {
    if (ownerId <= 0) return;
    _pendingOwnerIds.add(ownerId);
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(milliseconds: 300), () {
      final ids = Set<int>.from(_pendingOwnerIds);
      _pendingOwnerIds.clear();
      for (final id in ids) {
        unawaited(_syncOwner(id));
      }
    });
  }

  Future<void> _syncOwner(int ownerId) {
    final existing = _syncInFlightByOwner[ownerId];
    if (existing != null) return existing;
    final sync = () async {
      try {
        await _sessionRepository.loadChanges(ownerId: ownerId);
      } catch (error) {
        debugPrint(
          '[realtimeSync][changes-failed] owner=$ownerId error=$error',
        );
      }
    }();
    _syncInFlightByOwner[ownerId] = sync;
    return sync.whenComplete(() {
      if (identical(_syncInFlightByOwner[ownerId], sync)) {
        _syncInFlightByOwner.remove(ownerId);
      }
    });
  }

  Future<void> dispose() async {
    _syncTimer?.cancel();
    await _subscription?.cancel();
  }
}

final realtimeSyncCoordinatorProvider = Provider<RealtimeSyncCoordinator>((
  ref,
) {
  final coordinator = RealtimeSyncCoordinator(
    gateway: ref.watch(signalRGatewayProvider),
    sessionRepository: ref.watch(sessionRepositoryProvider),
    messageRepository: ref.watch(messageRepositoryProvider),
    onKicked: (reason) async {
      debugPrint('[realtimeSync][kicked] reason=$reason');
      await ref.read(authControllerProvider.notifier).logout();
    },
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});
