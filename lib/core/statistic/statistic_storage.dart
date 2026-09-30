import '../database/unified_database.dart';
import 'statistic_event.dart';

/// 统计事件本地存储接口
abstract class StatisticStorage {
  Future<void> enqueue(StatisticEvent event);
  Future<List<StatisticEvent>> getPendingEvents({int limit = 100});
  Future<void> removeEvents(List<String> eventIds);
  Future<void> updateRetry(List<String> eventIds, int delaySeconds);
  Future<int> getPendingCount();
  Future<List<StatisticEvent>> getRecentEvents({int limit = 50});
  Future<void> clearAll();
}

/// 基于 UnifiedDatabase (SQLite / Drift) 的统计存储实现
class DatabaseStatisticStorage implements StatisticStorage {
  const DatabaseStatisticStorage(this._database);

  final UnifiedDatabase _database;

  @override
  Future<void> enqueue(StatisticEvent event) async {
    final row = event.toDbRow();
    await _database.enqueueStatisticEvent(
      eventId: row['eventId'] as String,
      eventName: row['eventName'] as String,
      sessionId: row['sessionId'] as String?,
      page: row['page'] as String?,
      eventTime: (row['eventTime'] as num).toInt(),
      properties: row['properties'] as String?,
    );
  }

  @override
  Future<List<StatisticEvent>> getPendingEvents({int limit = 100}) async {
    final rows = await _database.readPendingStatisticEvents(limit: limit);
    return rows.map(StatisticEvent.fromDbRow).toList(growable: false);
  }

  @override
  Future<void> removeEvents(List<String> eventIds) async {
    if (eventIds.isEmpty) return;
    await _database.deleteStatisticEvents(eventIds);
  }

  @override
  Future<void> updateRetry(List<String> eventIds, int delaySeconds) async {
    if (eventIds.isEmpty) return;
    await _database.updateStatisticEventsRetry(
      eventIds: eventIds,
      delaySeconds: delaySeconds,
    );
  }

  @override
  Future<int> getPendingCount() async {
    return _database.countPendingStatisticEvents();
  }

  @override
  Future<List<StatisticEvent>> getRecentEvents({int limit = 50}) async {
    final rows = await _database.readRecentStatisticEvents(limit: limit);
    return rows.map(StatisticEvent.fromDbRow).toList(growable: false);
  }

  @override
  Future<void> clearAll() async {
    await _database.clearStatisticEventQueue();
  }
}
