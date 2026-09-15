import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ephemeral AI stream state. It is intentionally not a Drift model: final
/// replies arrive separately through the normal persisted message protocol.
class AiStreamEvent {
  const AiStreamEvent({
    required this.kind,
    required this.runId,
    required this.requesterSessionUnitId,
    required this.sourceMessageId,
    required this.sequence,
    this.delta = '',
    this.error = '',
    this.finalMessageId,
    this.startedAt,
    this.queueMilliseconds = 0,
    this.elapsedMilliseconds = 0,
  });

  final AiStreamEventKind kind;
  final String runId;
  final String requesterSessionUnitId;
  final int sourceMessageId;
  final int sequence;
  final String delta;
  final String error;
  final int? finalMessageId;
  final DateTime? startedAt;
  final int queueMilliseconds;
  final int elapsedMilliseconds;

  static AiStreamEvent? fromPayload(
    AiStreamEventKind kind,
    Object? payload, {
    DateTime? receivedAt,
  }) {
    if (payload is! Map) return null;
    final data = Map<String, dynamic>.from(payload);
    String value(String key) =>
        (data[key] ?? data['${key[0].toUpperCase()}${key.substring(1)}'])
            ?.toString() ??
        '';
    int? integer(String key) => int.tryParse(value(key));
    DateTime? dateTime(String key) => DateTime.tryParse(value(key))?.toUtc();
    final sourceMessageId = integer('sourceMessageId');
    final sequence = integer('sequence');
    final requesterSessionUnitId = value('requesterSessionUnitId');
    final runId = value('runId');
    if (sourceMessageId == null ||
        sequence == null ||
        requesterSessionUnitId.isEmpty ||
        runId.isEmpty) {
      return null;
    }
    return AiStreamEvent(
      kind: kind,
      runId: runId,
      requesterSessionUnitId: requesterSessionUnitId,
      sourceMessageId: sourceMessageId,
      sequence: sequence,
      delta: value('delta'),
      error: value('error'),
      finalMessageId: integer('finalMessageId'),
      // Older servers may not yet include timing fields. The client receive
      // time still gives a truthful running-duration baseline instead of
      // showing a permanently misleading 0ms.
      startedAt: dateTime('startedAt') ?? receivedAt?.toUtc(),
      queueMilliseconds: integer('queueMilliseconds') ?? 0,
      elapsedMilliseconds: integer('elapsedMilliseconds') ?? 0,
    );
  }
}

enum AiStreamEventKind { started, delta, completed, failed }

class AiStreamChangeBus {
  final StreamController<AiStreamEvent> _controller =
      StreamController<AiStreamEvent>.broadcast(sync: true);
  final Map<int, AiStreamSnapshot> _activeBySourceMessageId =
      <int, AiStreamSnapshot>{};

  Stream<AiStreamEvent> get events => _controller.stream;

  void publish(AiStreamEvent event) {
    final current = _activeBySourceMessageId[event.sourceMessageId];
    if (current != null &&
        current.runId == event.runId &&
        event.sequence <= current.sequence) {
      return;
    }
    final previous = current?.runId == event.runId ? current : null;
    _activeBySourceMessageId[event.sourceMessageId] = AiStreamSnapshot(
      runId: event.runId,
      requesterSessionUnitId: event.requesterSessionUnitId,
      sourceMessageId: event.sourceMessageId,
      sequence: event.sequence,
      text: switch (event.kind) {
        AiStreamEventKind.delta => '${previous?.text ?? ''}${event.delta}',
        _ => previous?.text ?? '',
      },
      status: switch (event.kind) {
        AiStreamEventKind.started => AiStreamStatus.thinking,
        AiStreamEventKind.delta => AiStreamStatus.streaming,
        AiStreamEventKind.completed => AiStreamStatus.completed,
        AiStreamEventKind.failed => AiStreamStatus.failed,
      },
      error:
          event.kind == AiStreamEventKind.failed
              ? (event.error.isEmpty ? 'AI 响应失败，请稍后重试。' : event.error)
              : previous?.error ?? '',
      startedAt: event.startedAt ?? previous?.startedAt,
      queueMilliseconds:
          event.queueMilliseconds > 0
              ? event.queueMilliseconds
              : previous?.queueMilliseconds ?? 0,
      elapsedMilliseconds: event.elapsedMilliseconds,
    );
    if (!_controller.isClosed) _controller.add(event);
  }

  List<AiStreamSnapshot> activeForRequesterSessionUnit(String sessionUnitId) =>
      _activeBySourceMessageId.values
          .where((item) => item.requesterSessionUnitId == sessionUnitId)
          .toList(growable: false);

  void removeBySourceMessageId(int sourceMessageId) {
    _activeBySourceMessageId.remove(sourceMessageId);
  }

  Future<void> dispose() => _controller.close();
}

enum AiStreamStatus { thinking, streaming, completed, failed }

class AiStreamSnapshot {
  const AiStreamSnapshot({
    required this.runId,
    required this.requesterSessionUnitId,
    required this.sourceMessageId,
    required this.sequence,
    required this.status,
    this.text = '',
    this.error = '',
    this.startedAt,
    this.queueMilliseconds = 0,
    this.elapsedMilliseconds = 0,
  });

  final String runId;
  final String requesterSessionUnitId;
  final int sourceMessageId;
  final int sequence;
  final AiStreamStatus status;
  final String text;
  final String error;
  final DateTime? startedAt;
  final int queueMilliseconds;
  final int elapsedMilliseconds;
}

final aiStreamChangeBusProvider = Provider<AiStreamChangeBus>((ref) {
  final bus = AiStreamChangeBus();
  ref.onDispose(bus.dispose);
  return bus;
});
