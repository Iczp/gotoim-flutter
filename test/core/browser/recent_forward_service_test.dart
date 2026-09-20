import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/browser/recent_forward_service.dart';
import 'package:gotoim_flutter/features/session/data/models/session_summary.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RecentForwardService', () {
    test('getRecentTargets prioritizes recorded sessions and falls back to active sessions', () async {
      final service = RecentForwardService.instance;

      final sessionA = SessionSummary.fromJson(const {
        'id': 'unit-a',
        'title': '文件传输助手',
      });
      final sessionB = SessionSummary.fromJson(const {
        'id': 'unit-b',
        'title': '陈凡',
      });
      final sessionC = SessionSummary.fromJson(const {
        'id': 'unit-c',
        'title': '张培坤',
      });

      final allSessions = [sessionA, sessionB, sessionC];

      // Record unit-b as recently forwarded
      await service.record('unit-b');

      final targets = service.getRecentTargets(allSessions: allSessions, limit: 3);

      expect(targets.length, 3);
      // unit-b should be at the head of the list
      expect(targets.first.id, 'unit-b');
      expect(targets[0].title, '陈凡');
      expect(targets.map((s) => s.id).toSet(), {'unit-a', 'unit-b', 'unit-c'});
    });
  });
}
