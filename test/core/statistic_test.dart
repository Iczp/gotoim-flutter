import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/statistic/statistic_api.dart';
import 'package:gotoim_flutter/core/statistic/statistic_device.dart';
import 'package:gotoim_flutter/core/statistic/statistic_event.dart';
import 'package:gotoim_flutter/core/statistic/statistic_event_names.dart';
import 'package:gotoim_flutter/core/statistic/statistic_page_names.dart';
import 'package:gotoim_flutter/core/statistic/statistic_repository.dart';
import 'package:gotoim_flutter/core/statistic/statistic_session.dart';
import 'package:gotoim_flutter/core/statistic/statistic_storage.dart';

class FakeStatisticStorage implements StatisticStorage {
  final List<StatisticEvent> list = <StatisticEvent>[];

  @override
  Future<void> enqueue(StatisticEvent event) async {
    list.add(event);
  }

  @override
  Future<List<StatisticEvent>> getPendingEvents({int limit = 100}) async {
    return list.take(limit).toList();
  }

  @override
  Future<void> removeEvents(List<String> eventIds) async {
    final set = eventIds.toSet();
    list.removeWhere((e) => set.contains(e.eventId));
  }

  @override
  Future<void> updateRetry(List<String> eventIds, int delaySeconds) async {}

  @override
  Future<int> getPendingCount() async => list.length;

  @override
  Future<List<StatisticEvent>> getRecentEvents({int limit = 50}) async =>
      list.reversed.take(limit).toList();

  @override
  Future<void> clearAll() async => list.clear();
}

class FakeStatisticApi implements StatisticApi {
  StatisticUploadResult uploadResult = const StatisticUploadResult(
    isSuccess: true,
    receivedCount: 1,
    successCount: 1,
  );

  StatisticDeviceInfo? lastDevice;
  List<StatisticEvent>? lastEvents;

  @override
  Future<StatisticUploadResult> uploadEvents({
    required StatisticDeviceInfo device,
    required List<StatisticEvent> events,
  }) async {
    lastDevice = device;
    lastEvents = events;
    return uploadResult;
  }
}

void main() {
  group('StatisticEvent Tests', () {
    test('Serializes to DbRow and restores correctly', () {
      final now = DateTime.now();
      final event = StatisticEvent(
        eventId: 'evt-123',
        eventName: StatisticEventNames.pageView,
        sessionId: 'session-456',
        page: StatisticPageNames.chatSession,
        eventTime: now,
        properties: {'durationSeconds': 42, 'source': 'tab'},
      );

      final row = event.toDbRow();
      expect(row['eventId'], 'evt-123');
      expect(row['eventName'], 'page_view');
      expect(row['sessionId'], 'session-456');
      expect(row['page'], 'chat.session');
      expect(row['eventTime'], now.millisecondsSinceEpoch);

      final restored = StatisticEvent.fromDbRow(row);
      expect(restored.eventId, event.eventId);
      expect(restored.eventName, event.eventName);
      expect(restored.sessionId, event.sessionId);
      expect(restored.page, event.page);
      expect(restored.properties?['durationSeconds'], 42);
      expect(restored.properties?['source'], 'tab');
    });

    test('Serializes to ApiDto format for backend compatibility', () {
      final event = StatisticEvent(
        eventId: 'evt-abc',
        eventName: StatisticEventNames.login,
        sessionId: 'sess-xyz',
        properties: {'method': 'password'},
      );

      final dto = event.toApiDto(
        fallbackPlatform: 'android',
        fallbackAppVersion: '1.0.0',
        fallbackOsVersion: '14',
        fallbackChannel: 'official',
      );

      expect(dto['eventId'], 'evt-abc');
      expect(dto['eventName'], 'login');
      expect(dto['sessionId'], 'sess-xyz');
      expect(dto['platform'], 'android');
      expect(dto['appVersion'], '1.0.0');
      expect(dto['properties'], isA<String>());
      final props = jsonDecode(dto['properties'] as String) as Map;
      expect(props['method'], 'password');
    });
  });

  group('StatisticSessionManager Tests', () {
    test('Generates new session and updates active time', () {
      final manager = StatisticSessionManager();
      final s1 = manager.currentSessionId;
      expect(s1, isNotEmpty);

      final s2 = manager.startNewSession();
      expect(s2, isNotEmpty);
      expect(s1, isNot(equals(s2)));
    });

    test(
        'App foreground under timeout keeps session, over timeout starts new session',
        () {
      final manager = StatisticSessionManager();
      final s1 = manager.currentSessionId;
      final baseTime = DateTime(2026, 9, 30, 12, 0, 0);

      manager.onAppBackground(baseTime);

      // 未超时 (比如后台停留 10 分钟，阈值 30 分钟)
      final changed1 = manager.onAppForeground(
        const Duration(minutes: 30),
        baseTime.add(const Duration(minutes: 10)),
      );
      expect(changed1, isFalse);
      expect(manager.currentSessionId, s1);

      // 再次进后台
      manager.onAppBackground(baseTime.add(const Duration(minutes: 10)));
      // 模拟超时 (后台停留 35 分钟，阈值 30 分钟)
      final changed2 = manager.onAppForeground(
        const Duration(minutes: 30),
        baseTime.add(const Duration(minutes: 45)),
      );
      expect(changed2, isTrue);
      expect(manager.currentSessionId, isNot(equals(s1)));
    });
  });

  group('StatisticPageNames Tests', () {
    test('Resolves known routes to canonical page names', () {
      expect(StatisticPageNames.resolvePageName('/'), StatisticPageNames.home);
      expect(StatisticPageNames.resolvePageName('/login'), StatisticPageNames.login);
      expect(
        StatisticPageNames.resolvePageName('/chat/12345'),
        StatisticPageNames.chatSession,
      );
      expect(
        StatisticPageNames.resolvePageName('/workbench'),
        StatisticPageNames.workbench,
      );
      expect(
        StatisticPageNames.resolvePageName('/settings/theme'),
        StatisticPageNames.settings,
      );
      expect(
        StatisticPageNames.resolvePageName('/account/profile'),
        StatisticPageNames.profile,
      );
    });
  });

  group('StatisticRepository Tests', () {
    test('Enqueue and upload batch with success deletes from storage', () async {
      final storage = FakeStatisticStorage();
      final api = FakeStatisticApi();
      final deviceManager = StatisticDeviceManager();
      final repo = StatisticRepository(
        storage: storage,
        api: api,
        deviceManager: deviceManager,
      );

      final evt1 = StatisticEvent(eventName: 'e1');
      final evt2 = StatisticEvent(eventName: 'e2');
      await repo.saveEvent(evt1);
      await repo.saveEvent(evt2);

      expect(await repo.getPendingCount(), 2);

      final result = await repo.uploadPendingBatch(
        appId: 'test-app',
        channel: 'official',
        limit: 10,
      );

      expect(result.isSuccess, isTrue);
      expect(api.lastEvents?.length, 2);
      expect(await repo.getPendingCount(), 0);
    });
  });
}
