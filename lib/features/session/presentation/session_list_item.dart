import '../data/models/session_summary.dart';

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
  final items = [...source]..sort((a, b) {
    final pinned = (b.isPinned ? 1 : 0).compareTo(a.isPinned ? 1 : 0);
    if (pinned != 0) return pinned;
    final score = b.score.compareTo(a.score);
    if (score != 0) return score;
    final ticks = b.ticks.compareTo(a.ticks);
    return ticks != 0 ? ticks : b.id.compareTo(a.id);
  });
  final result = <SessionListItem>[];
  final pinnedCount = items.where((item) => item.isPinned).length;
  String? previousCategory;
  for (var index = 0; index < items.length; index++) {
    final item = items[index];
    if (!item.isPinned && index == pinnedCount && pinnedCount > 0) {
      result.add(
        SessionListItem.pinnedDivider(count: pinnedCount, hasMore: hasMore),
      );
    }
    if (!item.isPinned) {
      final group = sessionTimeGroup(item.ticks, now: now);
      if (group != previousCategory) {
        final count =
            items
                .where(
                  (candidate) =>
                      !candidate.isPinned &&
                      sessionTimeGroup(candidate.ticks, now: now) == group,
                )
                .length;
        result.add(
          SessionListItem.timeDivider(
            title: group,
            count: count,
            hasMore: hasMore && index + count >= items.length,
          ),
        );
      }
      previousCategory = group;
    }
    result.add(SessionListItem.session(item));
  }
  return result;
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
