import 'package:flutter/material.dart';

import '../../data/models/message_sync_progress.dart';

/// Displays an unobtrusive bottom-aligned pill inside the message list area
/// with the active sync stage, completion ratio, and elapsed time.
class ChatSyncStatusPill extends StatelessWidget {
  const ChatSyncStatusPill({
    required this.progress,
    required this.elapsed,
    super.key,
  });

  final MessageSyncProgress? progress;
  final Duration elapsed;

  static String formatElapsed(Duration duration) {
    final totalMs = duration.isNegative ? 0 : duration.inMilliseconds;
    if (totalMs < 10000) {
      final seconds = (totalMs / 1000).toStringAsFixed(1);
      return '${seconds}s';
    }
    final totalSeconds = totalMs ~/ 1000;
    if (totalSeconds < 60) {
      return '${totalSeconds}s';
    }
    final minutes = totalSeconds ~/ 60;
    final remSeconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '${minutes}m ${remSeconds}s';
  }

  static String formatMessage(
    MessageSyncProgress? progress,
    Duration elapsed,
  ) {
    final elapsedText = formatElapsed(elapsed);
    final current = progress;
    if (current == null || current.stage == MessageSyncStage.fetchingLatest) {
      return '正在拉取最新消息... · $elapsedText';
    }
    if (current.stage == MessageSyncStage.calibrating) {
      final totalItems = current.totalItems;
      if (totalItems != null && totalItems > 0) {
        final percent = ((current.fraction ?? 0) * 100).round();
        final totalBatches = current.totalBatches;
        if (totalBatches != null && totalBatches > 1) {
          return '校准本地消息 ${current.processedItems}/$totalItems 条 ($percent%) · ${current.completedBatches}/$totalBatches 批 · $elapsedText';
        }
        return '校准本地消息 ${current.processedItems}/$totalItems 条 ($percent%) · $elapsedText';
      }
      return '正在校准本地消息... · $elapsedText';
    }
    if (current.stage == MessageSyncStage.pullingChanges) {
      if (current.processedItems > 0) {
        return '正在同步消息变更 (已处理 ${current.processedItems} 条) · $elapsedText';
      }
      return '正在同步消息变更... · $elapsedText';
    }
    return '正在同步消息... · $elapsedText';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fraction = progress?.fraction;
    final label = formatMessage(progress, elapsed);

    return IgnorePointer(
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          decoration: BoxDecoration(
            color:
                isDark
                    ? const Color(0xE6262B36)
                    : const Color(0xF0FFFFFF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color:
                  isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.08),
              width: 0.8,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.08),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      value: fraction,
                      strokeWidth: 1.8,
                      color: theme.colorScheme.primary,
                      backgroundColor:
                          theme.colorScheme.primary.withValues(alpha: 0.16),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.84,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (fraction != null) ...<Widget>[
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 2,
                    color: theme.colorScheme.primary,
                    backgroundColor:
                        theme.colorScheme.primary.withValues(alpha: 0.14),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
