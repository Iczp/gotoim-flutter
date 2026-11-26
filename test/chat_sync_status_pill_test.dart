import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/features/chat/data/models/message_sync_progress.dart';
import 'package:gotoim_flutter/features/chat/presentation/widgets/chat_sync_status_pill.dart';

void main() {
  test('formatElapsed formats sub-minute and minute durations cleanly', () {
    expect(
      ChatSyncStatusPill.formatElapsed(const Duration(milliseconds: 850)),
      '0.8s',
    );
    expect(
      ChatSyncStatusPill.formatElapsed(const Duration(seconds: 12)),
      '12s',
    );
    expect(
      ChatSyncStatusPill.formatElapsed(const Duration(seconds: 65)),
      '1m 05s',
    );
  });

  test('formatMessage displays stage progress, batches, and elapsed time', () {
    final calibrating = MessageSyncProgress(
      ownerId: 1,
      stage: MessageSyncStage.calibrating,
      startedAt: DateTime.now(),
      completedBatches: 1,
      totalBatches: 3,
      processedItems: 400,
      totalItems: 1000,
    );
    expect(
      ChatSyncStatusPill.formatMessage(
        calibrating,
        const Duration(seconds: 14),
      ),
      '校准本地消息 400/1000 条 (40%) · 1/3 批 · 14s',
    );

    final pulling = MessageSyncProgress(
      ownerId: 1,
      stage: MessageSyncStage.pullingChanges,
      startedAt: DateTime.now(),
      processedItems: 25,
    );
    expect(
      ChatSyncStatusPill.formatMessage(pulling, const Duration(seconds: 2)),
      '正在同步消息变更 (已处理 25 条) · 2.0s',
    );

    expect(
      ChatSyncStatusPill.formatMessage(null, const Duration(milliseconds: 700)),
      '正在拉取最新消息... · 0.7s',
    );
  });

  testWidgets('ChatSyncStatusPill renders label and progress indicators', (
    tester,
  ) async {
    final progress = MessageSyncProgress(
      ownerId: 1,
      stage: MessageSyncStage.calibrating,
      startedAt: DateTime.now(),
      completedBatches: 1,
      totalBatches: 2,
      processedItems: 250,
      totalItems: 500,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                bottom: 12,
                left: 16,
                right: 16,
                child: ChatSyncStatusPill(
                  progress: progress,
                  elapsed: const Duration(seconds: 3),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      find.text('校准本地消息 250/500 条 (50%) · 1/2 批 · 3.0s'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });
}
