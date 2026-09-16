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
      delta: value('delta').isNotEmpty ? value('delta') : value('previewText'),
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

  static AiStreamEvent? fromRecoveryPayload(Object? payload) {
    if (payload is! Map) return null;
    final data = Map<String, dynamic>.from(payload);
    final status = (data['status'] ?? data['Status'] ?? '').toString();
    final AiStreamEventKind? kind;
    if (status == 'running' || status == 'queued') {
      kind = AiStreamEventKind.started;
    } else if (status == 'streaming') {
      kind = AiStreamEventKind.delta;
    } else if (status == 'completed') {
      kind = AiStreamEventKind.completed;
    } else if (status == 'failed' || status == 'cancelled') {
      kind = AiStreamEventKind.failed;
    } else {
      kind = null;
    }
    return kind == null
        ? null
        : fromPayload(kind, data, receivedAt: DateTime.now());
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

  /// Replaces a snapshot with Redis recovery data rather than appending its
  /// preview text to an already received SignalR delta.
  void restore(AiStreamEvent event) {
    _activeBySourceMessageId[event.sourceMessageId] = AiStreamSnapshot(
      runId: event.runId,
      requesterSessionUnitId: event.requesterSessionUnitId,
      sourceMessageId: event.sourceMessageId,
      sequence: event.sequence,
      text: event.delta,
      status: switch (event.kind) {
        AiStreamEventKind.started => AiStreamStatus.thinking,
        AiStreamEventKind.delta => AiStreamStatus.streaming,
        AiStreamEventKind.completed => AiStreamStatus.completed,
        AiStreamEventKind.failed => AiStreamStatus.failed,
      },
      error: event.error,
      startedAt: event.startedAt,
      queueMilliseconds: event.queueMilliseconds,
      elapsedMilliseconds: event.elapsedMilliseconds,
    );
    if (!_controller.isClosed) _controller.add(event);
  }

  List<AiStreamSnapshot> activeForRequesterSessionUnit(String sessionUnitId) =>
      _activeBySourceMessageId.values
          .where((item) => item.requesterSessionUnitId == sessionUnitId)
          .toList(growable: false);

  /// Live runs are retained independently of the chat page so consumers such
  /// as the session list can start showing a running indicator even when they
  /// subscribe after SignalR has already delivered the first event.
  List<AiStreamSnapshot> get liveSnapshots => _activeBySourceMessageId.values
      .where(
        (item) =>
            item.status == AiStreamStatus.thinking ||
            item.status == AiStreamStatus.streaming,
      )
      .toList(growable: false);

  void removeBySourceMessageId(int sourceMessageId) {
    _activeBySourceMessageId.remove(sourceMessageId);
  }

  /// Removes transient snapshots when authoritative recovery says a
  /// conversation has no active AI run (HTTP 204).
  void removeForRequesterSessionUnit(String sessionUnitId) {
    _activeBySourceMessageId.removeWhere(
      (_, snapshot) => snapshot.requesterSessionUnitId == sessionUnitId,
    );
  }

  Future<void> dispose() => _controller.close();
}

enum AiStreamStatus { thinking, streaming, completed, failed }

/// A persisted AI run returned by `/api/chat/ai/recent/{sessionUnitId}`.
/// This is deliberately separate from [AiStreamSnapshot]: snapshots are live
/// transport state, whereas a record is Redis recovery/history data.
class AiRunRecord {
  const AiRunRecord({
    required this.runId,
    required this.sourceMessageId,
    required this.status,
    required this.updatedAt,
    required this.queueMilliseconds,
    required this.elapsedMilliseconds,
    required this.sequence,
    required this.previewText,
    required this.error,
    required this.timeline,
    this.finalMessageId,
  });

  final String runId;
  final int sourceMessageId;
  final String status;
  final DateTime? updatedAt;
  final int queueMilliseconds;
  final int elapsedMilliseconds;
  final int sequence;
  final String previewText;
  final String error;
  final int? finalMessageId;
  final List<AiRunTimelineItem> timeline;

  factory AiRunRecord.fromJson(Map<String, dynamic> data) => AiRunRecord(
    runId: '${data['runId'] ?? ''}',
    sourceMessageId: _asInt(data['sourceMessageId']) ?? 0,
    status: '${data['status'] ?? 'unknown'}',
    updatedAt: DateTime.tryParse('${data['updatedAt'] ?? ''}')?.toLocal(),
    queueMilliseconds: _asInt(data['queueMilliseconds']) ?? 0,
    elapsedMilliseconds: _asInt(data['elapsedMilliseconds']) ?? 0,
    sequence: _asInt(data['sequence']) ?? 0,
    previewText: '${data['previewText'] ?? ''}',
    error: '${data['error'] ?? ''}',
    finalMessageId: _asInt(data['finalMessageId']),
    timeline: (data['timeline'] as List? ?? const <dynamic>[])
        .whereType<Map>()
        .map(
          (item) => AiRunTimelineItem.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false),
  );
}

class AiRunTimelineItem {
  const AiRunTimelineItem({
    required this.occurredAt,
    required this.eventType,
    required this.status,
    required this.sequence,
    required this.elapsedMilliseconds,
    required this.detail,
  });

  final DateTime? occurredAt;
  final String eventType;
  final String status;
  final int sequence;
  final int elapsedMilliseconds;
  final String detail;

  factory AiRunTimelineItem.fromJson(Map<String, dynamic> data) =>
      AiRunTimelineItem(
        occurredAt: DateTime.tryParse('${data['occurredAt'] ?? ''}')?.toLocal(),
        eventType: '${data['eventType'] ?? ''}',
        status: '${data['status'] ?? ''}',
        sequence: _asInt(data['sequence']) ?? 0,
        elapsedMilliseconds: _asInt(data['elapsedMilliseconds']) ?? 0,
        detail: '${data['detail'] ?? ''}',
      );
}

int? _asInt(Object? value) =>
    value is num ? value.toInt() : int.tryParse('${value ?? ''}');

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
