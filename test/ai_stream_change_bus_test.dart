import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/features/chat/application/ai_stream_change_bus.dart';

void main() {
  test('parses an Aurora delta event without persisting message fields', () {
    final event =
        AiStreamEvent.fromPayload(AiStreamEventKind.delta, <String, dynamic>{
          'runId': 'run-1',
          'requesterSessionUnitId': 'session-unit-1',
          'sourceMessageId': 7297610,
          'sequence': 3,
          'delta': '正在生成',
          'startedAt': '2026-09-15T05:00:00.000Z',
          'queueMilliseconds': 230,
          'elapsedMilliseconds': 1280,
        });

    expect(event, isNotNull);
    expect(event!.kind, AiStreamEventKind.delta);
    expect(event.sourceMessageId, 7297610);
    expect(event.sequence, 3);
    expect(event.delta, '正在生成');
    expect(event.queueMilliseconds, 230);
    expect(event.elapsedMilliseconds, 1280);
    expect(event.startedAt, DateTime.utc(2026, 9, 15, 5));
  });

  test('rejects incomplete transient payloads', () {
    final event = AiStreamEvent.fromPayload(
      AiStreamEventKind.started,
      <String, dynamic>{'runId': 'run-1'},
    );

    expect(event, isNull);
  });

  test('keeps a running reply available when a chat page is reopened', () {
    final bus = AiStreamChangeBus();
    bus.publish(
      const AiStreamEvent(
        kind: AiStreamEventKind.started,
        runId: 'run-1',
        requesterSessionUnitId: 'session-unit-1',
        sourceMessageId: 7297610,
        sequence: 0,
      ),
    );
    bus.publish(
      const AiStreamEvent(
        kind: AiStreamEventKind.delta,
        runId: 'run-1',
        requesterSessionUnitId: 'session-unit-1',
        sourceMessageId: 7297610,
        sequence: 1,
        delta: '已生成的一部分',
      ),
    );

    final restored = bus.activeForRequesterSessionUnit('session-unit-1');

    expect(restored, hasLength(1));
    expect(restored.single.text, '已生成的一部分');
    expect(restored.single.status, AiStreamStatus.streaming);
  });

  test('Redis recovery replaces transient preview and final event is ordered', () {
    final bus = AiStreamChangeBus();
    bus.publish(
      const AiStreamEvent(
        kind: AiStreamEventKind.delta,
        runId: 'run-1',
        requesterSessionUnitId: 'session-unit-1',
        sourceMessageId: 7297610,
        sequence: 2,
        delta: '旧的瞬时片段',
      ),
    );
    final recovered = AiStreamEvent.fromRecoveryPayload(<String, dynamic>{
      'runId': 'run-1',
      'requesterSessionUnitId': 'session-unit-1',
      'sourceMessageId': 7297610,
      'sequence': 4,
      'status': 'streaming',
      'previewText': 'Redis 中完整预览',
      'startedAt': '2026-09-15T05:00:00.000Z',
    });
    bus.restore(recovered!);
    bus.publish(
      const AiStreamEvent(
        kind: AiStreamEventKind.completed,
        runId: 'run-1',
        requesterSessionUnitId: 'session-unit-1',
        sourceMessageId: 7297610,
        sequence: 5,
        finalMessageId: 7297611,
      ),
    );

    final snapshot = bus.activeForRequesterSessionUnit('session-unit-1').single;
    expect(snapshot.text, 'Redis 中完整预览');
    expect(snapshot.status, AiStreamStatus.completed);
    expect(snapshot.sequence, 5);
  });
}
