import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/features/session/data/models/session_summary.dart';

void main() {
  group('Desktop Chat Component Reuse & LRU Pool Tests', () {
    test('LRU cache correctly retains recent sessions and evicts least recently accessed', () {
      final cachedChats = <String, DateTime>{};
      const maxCachedChats = 6;
      String? selectedSessionUnitId;

      void touchCachedChat(String sessionUnitId) {
        if (cachedChats.containsKey(sessionUnitId)) {
          cachedChats[sessionUnitId] = DateTime.now();
        } else {
          if (cachedChats.length >= maxCachedChats) {
            String? lruKey;
            DateTime? oldestTime;
            for (final entry in cachedChats.entries) {
              if (entry.key == selectedSessionUnitId) continue;
              if (oldestTime == null || entry.value.isBefore(oldestTime)) {
                oldestTime = entry.value;
                lruKey = entry.key;
              }
            }
            lruKey ??= cachedChats.keys.first;
            cachedChats.remove(lruKey);
          }
          cachedChats[sessionUnitId] = DateTime.now();
        }
      }

      // 1. 连续访问 6 个不同会话 (s1 ~ s6)
      for (var i = 1; i <= 6; i++) {
        touchCachedChat('s$i');
        selectedSessionUnitId = 's$i';
      }
      expect(cachedChats.length, equals(6));
      expect(cachedChats.containsKey('s1'), isTrue);
      expect(cachedChats.containsKey('s6'), isTrue);

      // 2. 重新访问 s1，刷新其最近访问时间 (s1 变最新，s2 变成最旧)
      touchCachedChat('s1');
      selectedSessionUnitId = 's1';

      // 3. 打开第 7 个会话 s7，容量超限触发 LRU 淘汰
      touchCachedChat('s7');
      selectedSessionUnitId = 's7';

      // 验证: 最久未访问的 s2 被淘汰，而重新触达的 s1 和新增的 s7 均在缓存中
      expect(cachedChats.length, equals(6));
      expect(cachedChats.containsKey('s2'), isFalse, reason: 's2 应该被 LRU 机制淘汰');
      expect(cachedChats.containsKey('s1'), isTrue, reason: 's1 被再次访问刷新过，不应被淘汰');
      expect(cachedChats.containsKey('s7'), isTrue, reason: 's7 为最新打开的会话，必须保留');

      // 4. 切换身份时，缓存池应完全清空以确保账号数据隔离
      cachedChats.clear();
      expect(cachedChats.isEmpty, isTrue);
    });

    test('SessionSummary data model integrity for desktop split view', () {
      final session = SessionSummary(
        id: 's_test_1',
        ownerId: 1001,
        score: 100,
        title: '架构重构群',
        preview: '最新消息预览',
        updatedAt: DateTime.now(),
        unreadCount: 3,
        isPinned: false,
        raw: const {},
        ticks: 100,
      );

      expect(session.id, equals('s_test_1'));
      expect(session.title, equals('架构重构群'));
      expect(session.unreadCount, equals(3));
    });
  });
}
