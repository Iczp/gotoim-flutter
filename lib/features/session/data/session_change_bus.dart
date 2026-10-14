import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

class SessionChangeEvent {
  const SessionChangeEvent({
    required this.ownerId,
    required this.sessionUnitId,
    this.messageId,
  });
  final int ownerId;
  final String sessionUnitId;
  final int? messageId;
}

class SessionChangeBus {
  final StreamController<SessionChangeEvent> _controller =
      StreamController<SessionChangeEvent>.broadcast(sync: true);

  Stream<SessionChangeEvent> get events => _controller.stream;

  void publish({
    required int ownerId,
    required String sessionUnitId,
    int? messageId,
  }) {
    if (!_controller.isClosed) {
      _controller.add(
        SessionChangeEvent(
          ownerId: ownerId,
          sessionUnitId: sessionUnitId,
          messageId: messageId,
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
