import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

class SessionChangeEvent {
  const SessionChangeEvent({
    required this.ownerId,
    required this.sessionUnitId,
    this.messageId,
    this.messageIds,
    this.deletedMessageIds,
  });
  final int ownerId;
  final String sessionUnitId;
  final int? messageId;
  final List<int>? messageIds;
  final List<int>? deletedMessageIds;
}

class SessionChangeBus {
  final StreamController<SessionChangeEvent> _controller =
      StreamController<SessionChangeEvent>.broadcast(sync: true);

  Stream<SessionChangeEvent> get events => _controller.stream;

  void publish({
    required int ownerId,
    required String sessionUnitId,
    int? messageId,
    List<int>? messageIds,
    List<int>? deletedMessageIds,
  }) {
    if (!_controller.isClosed) {
      _controller.add(
        SessionChangeEvent(
          ownerId: ownerId,
          sessionUnitId: sessionUnitId,
          messageId: messageId,
          messageIds: messageIds == null ? null : List.unmodifiable(messageIds),
          deletedMessageIds:
              deletedMessageIds == null
                  ? null
                  : List.unmodifiable(deletedMessageIds),
        ),
      );
    }
  }

  Future<void> dispose() => _controller.close();
}

final sessionChangeBusProvider = Provider<SessionChangeBus>((ref) {
  final bus = SessionChangeBus();
  ref.onDispose(bus.dispose);
  return bus;
});
