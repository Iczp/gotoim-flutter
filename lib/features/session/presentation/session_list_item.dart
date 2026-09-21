import 'package:flutter/material.dart';

import '../data/models/session_summary.dart';
import 'session_dividers.dart';
import 'session_unit_item.dart';

export 'session_dividers.dart';
export 'session_unit_item.dart';

enum SessionListItemKind { session, pinnedDivider, timeDivider }

class SessionListItem {
  const SessionListItem._({
    required this.kind,
    this.session,
    this.title,
    this.count = 0,
    this.hasMore = false,
  });

  factory SessionListItem.session(SessionSummary session) =>
      SessionListItem._(kind: SessionListItemKind.session, session: session);

  factory SessionListItem.pinnedDivider({
    required int count,
    required bool hasMore,
  }) => SessionListItem._(
    kind: SessionListItemKind.pinnedDivider,
    title: '以上是置顶会话',
    count: count,
    hasMore: hasMore,
  );

  factory SessionListItem.timeDivider({
    required String title,
    required int count,
    required bool hasMore,
  }) => SessionListItem._(
    kind: SessionListItemKind.timeDivider,
    title: title,
    count: count,
    hasMore: hasMore,
  );

  final SessionListItemKind kind;
  final SessionSummary? session;
  final String? title;
  final int count;
  final bool hasMore;
}

List<SessionListItem> buildSessionListItems(
  List<SessionSummary> source, {
  required bool hasMore,
  DateTime? now,
}) {
  // Score is the server-owned global order: Sorting * 1e13 + Ticks.  Time
  // dividers are only presentational and must never change that order.
  final items = [...source]..sort(_compareSessions);
  final pinnedCount = items.where((item) => item.isPinned).length;
  final timeGroupCounts = <String, int>{};
  for (final item in items.where((item) => !item.isPinned)) {
    final group = sessionTimeGroup(item.ticks, now: now);
    timeGroupCounts[group] = (timeGroupCounts[group] ?? 0) + 1;
  }
  final result = <SessionListItem>[];
  String? previousTimeGroup;
  var emittedPinnedDivider = false;
  for (final item in items) {
    if (item.isPinned) {
      result.add(SessionListItem.session(item));
      continue;
    }
    if (!emittedPinnedDivider && pinnedCount > 0) {
      result.add(
        SessionListItem.pinnedDivider(count: pinnedCount, hasMore: false),
      );
      emittedPinnedDivider = true;
    }
    final timeGroup = sessionTimeGroup(item.ticks, now: now);
    if (timeGroup != previousTimeGroup) {
      result.add(
        SessionListItem.timeDivider(
          title: timeGroup,
          count: timeGroupCounts[timeGroup] ?? 0,
          hasMore: false,
        ),
      );
      previousTimeGroup = timeGroup;
    }
    result.add(SessionListItem.session(item));
  }
  if (hasMore && result.isNotEmpty) {
    final last = result.last;
    if (last.kind == SessionListItemKind.session) {
      // The loading affordance belongs to the final rendered section.  Keep
      // ordering data separate from presentation metadata.
      final dividerIndex = result.lastIndexWhere(
        (item) => item.kind == SessionListItemKind.timeDivider,
      );
      if (dividerIndex >= 0) {
        final divider = result[dividerIndex];
        result[dividerIndex] = SessionListItem.timeDivider(
          title: divider.title ?? '',
          count: divider.count,
          hasMore: true,
        );
      }
    }
  }
  return result;
}

int _compareSessions(SessionSummary a, SessionSummary b) {
  final score = b.score.compareTo(a.score);
  if (score != 0) return score;
  final ticks = b.ticks.compareTo(a.ticks);
  return ticks != 0 ? ticks : b.id.compareTo(a.id);
}

String sessionTimeGroup(int ticks, {DateTime? now}) {
  if (ticks <= 0) return '很久以前（5年前以上）';
  final current = now ?? DateTime.now();
  final value = DateTime.fromMillisecondsSinceEpoch(ticks);
  final today = DateTime(current.year, current.month, current.day);
  final date = DateTime(value.year, value.month, value.day);
  final days = today.difference(date).inDays;
  if (days <= 0) return '今天';
  if (days == 1) return '昨天';
  if (days < 3) return '三天前';
  if (days < 7) return '近一周';
  if (days < 14) return '两周前';
  if (days < 30) return '一个月前';
  if (days < 60) return '两个月前';
  if (days < 90) return '三个月前';
  if (days < 180) return '半年前';
  if (days < 365) return '1年前';
  if (days < 730) return '2年前';
  if (days < 1095) return '3年前';
  if (days < 1460) return '4年前';
  return '很久以前（5年前以上）';
}

/// A theme-adapted and overflow-protected widget for rendering any [SessionListItem].
class SessionListItemView extends StatelessWidget {
  const SessionListItemView({
    required this.item,
    this.onTap,
    this.onLongPress,
    this.showDivider = true,
    this.dividerIndent = 74.0,
    this.dividerEndIndent = 0.0,
    this.aiRunning = false,
    super.key,
  });

  final SessionListItem item;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool showDivider;
  final double dividerIndent;
  final double dividerEndIndent;
  final bool aiRunning;

  @override
  Widget build(BuildContext context) {
    return switch (item.kind) {
      SessionListItemKind.session => SessionUnitItem(
        key: ValueKey(item.session!.id),
        item: item.session!,
        onTap: onTap,
        onLongPress: onLongPress,
        showDivider: showDivider,
        dividerIndent: dividerIndent,
        dividerEndIndent: dividerEndIndent,
        aiRunning: aiRunning,
      ),
      SessionListItemKind.pinnedDivider => PinnedDividerItem(
        key: const ValueKey('pinned_divider'),
        count: item.count,
        hasMore: item.hasMore,
      ),
      SessionListItemKind.timeDivider => TimeDividerItem(
        key: ValueKey('time_divider_${item.title}'),
        text: item.title ?? '',
        count: item.count,
        hasMore: item.hasMore,
      ),
    };
  }
}
