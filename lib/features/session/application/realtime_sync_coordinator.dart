import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_navigation.dart';
import '../../../core/network/session_invalidator.dart';
import '../../../core/realtime/signalr_gateway.dart';
import '../../auth/application/auth_controller.dart';
import '../../chat/application/chat_controller.dart';
import '../../chat/application/ai_stream_change_bus.dart';
import '../../chat/data/repositories/message_repository.dart';
import 'active_chat_registry.dart';
import 'session_list_controller.dart';
import '../data/repositories/session_repository.dart';
import 'message_alert_coordinator.dart';

/// The sole application-level consumer that turns realtime notifications into
/// persisted IM state. Pages observe repository change buses instead of the
/// SignalR transport, so a closed chat cannot miss an incoming message.
class RealtimeSyncCoordinator {
  RealtimeSyncCoordinator({
    required SignalRGateway gateway,
    required SessionRepository sessionRepository,
    required MessageRepository messageRepository,
    required AiStreamChangeBus aiStreamChangeBus,
    required MessageAlertCoordinator messageAlertCoordinator,
    required ActiveChatRegistry activeChatRegistry,
    required Future<void> Function(String reason) onKicked,
  }) : _gateway = gateway,
       _sessionRepository = sessionRepository,
       _messageRepository = messageRepository,
       _aiStreamChangeBus = aiStreamChangeBus,
       _messageAlertCoordinator = messageAlertCoordinator,
       _activeChatRegistry = activeChatRegistry,
       _onKicked = onKicked;

  final SignalRGateway _gateway;
  final SessionRepository _sessionRepository;
  final MessageRepository _messageRepository;
  final AiStreamChangeBus _aiStreamChangeBus;
  final MessageAlertCoordinator _messageAlertCoordinator;
  final ActiveChatRegistry _activeChatRegistry;
  final Future<void> Function(String reason) _onKicked;
  StreamSubscription<SignalRAppEvent>? _subscription;
  Timer? _syncTimer;
  final Set<int> _pendingOwnerIds = <int>{};
  final Map<int, Future<void>> _syncInFlightByOwner = <int, Future<void>>{};
  final Map<String, Future<void>> _unitSyncInFlight = <String, Future<void>>{};
  final Set<int> _ownerResyncRequested = {};
  bool _disposed = false;
  bool _kicked = false;

  void start() {
    _subscription ??= _gateway.events.listen(_onEvent);
    _scheduleCurrentOwnerSync();
  }

  Future<void> syncCurrentOwner() async {
    final owner = await _sessionRepository.readCurrentOwnerId();
    if (owner != null && owner > 0) await _syncOwner(owner);
  }

  void _onEvent(SignalRAppEvent event) {
    if (event is SignalRConnectionEvent &&
        event.state == SignalRConnectionState.connected) {
      _kicked = false;
      _scheduleCurrentOwnerSync();
      return;
    }
    if (event is! SignalRCommandEvent) return;
    switch (event.command) {
      case SignalRCommand.kicked:
        if (_kicked) break;
        _kicked = true;
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
        unawaited(_scheduleTargetedSync(event));
        break;
      case SignalRCommand.messageDeleted:
        unawaited(_handleMessageDeletion(event));
        break;
      case SignalRCommand.sessionUnitChanged:
        // Read/badge updates do not necessarily change the conversation
        // watermark. Sync the exact affected unit instead of re-querying the
        // owner-wide /changes endpoint.
        unawaited(_syncChangedSessionUnit(event));
        break;
      case SignalRCommand.aiStarted:
        _publishAiEvent(
          AiStreamEventKind.started,
          event.payload,
          event.receivedAt,
        );
        break;
      case SignalRCommand.aiDelta:
        _publishAiEvent(
          AiStreamEventKind.delta,
          event.payload,
          event.receivedAt,
        );
        break;
      case SignalRCommand.aiCompleted:
        _publishAiEvent(
          AiStreamEventKind.completed,
          event.payload,
          event.receivedAt,
        );
        break;
      case SignalRCommand.aiFailed:
        _publishAiEvent(
          AiStreamEventKind.failed,
          event.payload,
          event.receivedAt,
        );
        break;
      default:
        break;
    }
  }

  void _publishAiEvent(
    AiStreamEventKind kind,
    Object? payload,
    DateTime receivedAt,
  ) {
    final event = AiStreamEvent.fromPayload(
      kind,
      payload,
      receivedAt: receivedAt,
    );
    if (event == null) {
      debugPrint('[realtimeSync][ai-stream-invalid] kind=${kind.name}');
      return;
    }
    _aiStreamChangeBus.publish(event);
  }

  Future<void> _handleMessageDeletion(SignalRCommandEvent event) async {
    try {
      for (final scope in event.scopes.whereType<Map>()) {
        final unit =
            '${scope['sessionUnitId'] ?? scope['SessionUnitId'] ?? ''}';
        if (unit.isEmpty) continue;
        final friend = await _sessionRepository.loadLocalFriendDetail(unit);
        final owner = friend?.ownerId;
        if (owner != null) {
          await _messageRepository.loadChanges(
            ownerId: owner,
            sessionUnitId: unit,
          );
        } else {
          _scheduleCurrentOwnerSync();
        }
      }
    } catch (error) {
      debugPrint('[realtimeSync][delete-sync-failed] error=$error');
      _scheduleCurrentOwnerSync();
    }
  }

  Future<void> _handleRealtimeMessage(SignalRCommandEvent event) async {
    try {
      final sessionUnitIds =
          event.scopes
              .whereType<Map>()
              .map((scope) => scope['sessionUnitId'] ?? scope['SessionUnitId'])
              .whereType<Object>()
              .map((id) => '$id')
              .where((id) => id.isNotEmpty)
              .toSet();
      final changedOwnerIds = <int>{};
      for (final sessionUnitId in sessionUnitIds) {
        final message = await _messageRepository
            .applyRealtimePayloadFromCachedSession(
              event.payload,
              sessionUnitId: sessionUnitId,
            );
        if (message != null) {
          changedOwnerIds.add(message.ownerId);
          if (event.command == SignalRCommand.messageCreated ||
              event.command == SignalRCommand.messageForwarded) {
            final session = await _sessionRepository.loadLocalFriendDetail(
              sessionUnitId,
            );
            await _messageAlertCoordinator.handleIncoming(
              message: message,
              session: session,
            );
          }
        }
      }
      if (changedOwnerIds.isNotEmpty) {
        for (final ownerId in changedOwnerIds) {
          _scheduleOwnerSync(ownerId);
        }
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

  Future<void> _syncChangedSessionUnit(SignalRCommandEvent event) async {
    final sessionUnitId = _extractSessionUnitId(event.payload);
    if (sessionUnitId == null || sessionUnitId.isEmpty) {
      _scheduleCurrentOwnerSync();
      return;
    }

    var ownerId = _extractOwnerId(event.payload);
    if (ownerId == null || ownerId <= 0) {
      ownerId =
          (await _sessionRepository.loadLocalFriendDetail(
            sessionUnitId,
          ))?.ownerId;
    }
    if (ownerId == null || ownerId <= 0) {
      _scheduleCurrentOwnerSync();
      return;
    }

    // A foreground chat has already persisted its own set-read response and
    // listens to the shared cache change bus. Its SignalR echo must not cause
    // a second `/friend/{id}` request; the owner-wide incremental sync keeps
    // any additional session fields current.
    if (_activeChatRegistry.isForegroundSession(sessionUnitId)) {
      _scheduleOwnerSync(ownerId);
      return;
    }

    final key = '$ownerId/$sessionUnitId';
    final existing = _unitSyncInFlight[key];
    if (existing != null) return existing;
    final sync = () async {
      try {
        await _sessionRepository.loadRemoteFriendDetail(
          ownerId: ownerId!,
          sessionUnitId: sessionUnitId,
        );
      } catch (error) {
        debugPrint(
          '[realtimeSync][session-unit-detail-failed] '
          'owner=$ownerId session=$sessionUnitId error=$error',
        );
      }
    }();
    _unitSyncInFlight[key] = sync;
    return sync.whenComplete(() {
      if (identical(_unitSyncInFlight[key], sync)) {
        _unitSyncInFlight.remove(key);
      }
    });
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
    final sessionUnit = map['sessionUnit'] ?? map['SessionUnit'];
    if (sessionUnit is Map) {
      final unitMap = Map<String, dynamic>.from(sessionUnit);
      final rawUnitOwnerId = unitMap['ownerId'] ?? unitMap['OwnerId'];
      if (rawUnitOwnerId is num) return rawUnitOwnerId.toInt();
      if (rawUnitOwnerId is String) return int.tryParse(rawUnitOwnerId);
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
    if (_disposed || ownerId <= 0) return;
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
    if (existing != null) {
      _ownerResyncRequested.add(ownerId);
      return existing;
    }
    final sync = () async {
      try {
        await _sessionRepository.loadChanges(ownerId: ownerId);
        await _messageRepository.loadChanges(ownerId: ownerId);
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
        if (_ownerResyncRequested.remove(ownerId)) _scheduleOwnerSync(ownerId);
      }
    });
  }

  Future<void> dispose() async {
    _disposed = true;
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
    aiStreamChangeBus: ref.watch(aiStreamChangeBusProvider),
    messageAlertCoordinator: ref.watch(messageAlertCoordinatorProvider),
    activeChatRegistry: ref.watch(activeChatRegistryProvider),
    onKicked: (reason) async {
      if (ref.read(authControllerProvider).status ==
          AuthStatus.unauthenticated) {
        return;
      }
      debugPrint('[realtimeSync][kicked] reason=$reason');
      await ref
          .read(sessionInvalidatorProvider)
          .invalidate(reason: reason);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = rootNavigatorKey.currentContext;
        if (context == null || !context.mounted) return;
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder:
              (dialogContext) => AlertDialog(
                title: const Text('该设备已退出登录'),
                content: Text('原因：${reason.isEmpty ? '未知原因' : reason}'),
                actions: <Widget>[
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('确定'),
                  ),
                ],
              ),
        );
      });
    },
  );
  ref.onDispose(coordinator.dispose);
  ref.listen<int?>(
    sessionListControllerProvider.select((state) => state.currentOwnerId),
    (previous, next) {
      if (next != null && next != previous) {
        coordinator._scheduleOwnerSync(next);
      }
    },
    fireImmediately: true,
  );
  return coordinator;
});
