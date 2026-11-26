enum MessageSyncStage {
  idle,
  pullingChanges,
  calibrating,
  fetchingLatest,
}

class MessageSyncProgress {
  const MessageSyncProgress({
    required this.ownerId,
    required this.stage,
    required this.startedAt,
    this.completedBatches = 0,
    this.totalBatches,
    this.processedItems = 0,
    this.totalItems,
    this.processedSessions = 0,
    this.totalSessions,
  });

  factory MessageSyncProgress.idle(int ownerId) => MessageSyncProgress(
    ownerId: ownerId,
    stage: MessageSyncStage.idle,
    startedAt: DateTime.now(),
  );

  final int ownerId;
  final MessageSyncStage stage;
  final DateTime startedAt;
  final int completedBatches;
  final int? totalBatches;
  final int processedItems;
  final int? totalItems;
  final int processedSessions;
  final int? totalSessions;

  bool get isActive => stage != MessageSyncStage.idle;

  double? get fraction {
    final totalI = totalItems;
    if (totalI != null && totalI > 0) {
      return (processedItems / totalI).clamp(0.0, 1.0);
    }
    final totalB = totalBatches;
    if (totalB != null && totalB > 0) {
      return (completedBatches / totalB).clamp(0.0, 1.0);
    }
    return null;
  }
}
