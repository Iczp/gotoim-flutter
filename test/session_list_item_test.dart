import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/features/session/data/models/session_summary.dart';
import 'package:gotoim_flutter/features/session/presentation/session_list_item.dart';

void main() {
  final now = DateTime(2026, 8, 26, 12);

  SessionSummary session({
    required String id,
    required int ticks,
    int? score,
    bool pinned = false,
  }) => SessionSummary.fromJson({
    'id': id,
    'ownerId': 1,
    'score': score ?? ticks,
    'ticks': ticks,
    'sorting': pinned ? 1 : 0,
    'destination': {'name': id},
  });

  test('sessions are ordered by score inside their pinned group', () {
    final items = buildSessionListItems(
      [
        session(id: 'newer-time', ticks: 200, score: 10),
        session(id: 'higher-score', ticks: 100, score: 20),
      ],
      hasMore: false,
      now: now,
    );

    final sessions =
        items
            .where((item) => item.kind == SessionListItemKind.session)
            .map((item) => item.session!.id)
            .toList();
    expect(sessions, <String>['higher-score', 'newer-time']);
  });

  test('pinned sessions form a separate group before time groups', () {
    final items = buildSessionListItems(
      [
        session(id: 'today', ticks: now.millisecondsSinceEpoch),
        session(
          id: 'pinned',
          ticks: now.subtract(const Duration(days: 20)).millisecondsSinceEpoch,
          pinned: true,
        ),
      ],
      hasMore: false,
      now: now,
    );

    expect(items.map((item) => item.kind), [
      SessionListItemKind.session,
      SessionListItemKind.pinnedDivider,
      SessionListItemKind.timeDivider,
      SessionListItemKind.session,
    ]);
    expect(items[1].count, 1);
    expect(items[2].title, '今天');
  });

  test(
    'each time group is emitted once when score order interleaves groups',
    () {
      final items = buildSessionListItems(
        [
          session(
            id: 'month-low-score',
            ticks:
                now.subtract(const Duration(days: 20)).millisecondsSinceEpoch,
            score: 10,
          ),
          session(
            id: 'year',
            ticks:
                now.subtract(const Duration(days: 200)).millisecondsSinceEpoch,
            score: 30,
          ),
          session(
            id: 'month-high-score',
            ticks:
                now.subtract(const Duration(days: 25)).millisecondsSinceEpoch,
            score: 20,
          ),
        ],
        hasMore: false,
        now: now,
      );

      final dividers =
          items
              .where((item) => item.kind == SessionListItemKind.timeDivider)
              .map((item) => item.title)
              .toList();
      expect(dividers, <String>['一个月前', '1年前']);
      expect(
        items
            .where((item) => item.kind == SessionListItemKind.session)
            .map((item) => item.session!.id),
        <String>['month-high-score', 'month-low-score', 'year'],
      );
    },
  );

  test('time groups match UniApp boundaries', () {
    expect(sessionTimeGroup(now.millisecondsSinceEpoch, now: now), '今天');
    expect(
      sessionTimeGroup(
        now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
        now: now,
      ),
      '昨天',
    );
    expect(
      sessionTimeGroup(
        now.subtract(const Duration(days: 4)).millisecondsSinceEpoch,
        now: now,
      ),
      '近一周',
    );
    expect(
      sessionTimeGroup(
        now.subtract(const Duration(days: 400)).millisecondsSinceEpoch,
        now: now,
      ),
      '2年前',
    );
    expect(
      sessionTimeGroup(
        now.subtract(const Duration(days: 1500)).millisecondsSinceEpoch,
        now: now,
      ),
      '很久以前（5年前以上）',
    );
  });
}
