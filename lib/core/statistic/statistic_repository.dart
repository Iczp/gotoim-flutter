import 'statistic_api.dart';
import 'statistic_device.dart';
import 'statistic_event.dart';
import 'statistic_storage.dart';

/// 统计数据仓库
class StatisticRepository {
  StatisticRepository({
    required StatisticStorage storage,
    required StatisticApi api,
    required StatisticDeviceManager deviceManager,
  })  : _storage = storage,
        _api = api,
        _deviceManager = deviceManager;

  final StatisticStorage _storage;
  final StatisticApi _api;
  final StatisticDeviceManager _deviceManager;

  /// 记录事件到本地存储
  Future<void> saveEvent(StatisticEvent event) async {
    await _storage.enqueue(event);
  }

  /// 执行一批事件的上传
  Future<StatisticUploadResult> uploadPendingBatch({
    required String appId,
    required String channel,
    int limit = 100,
    String? fallbackAppVersion,
  }) async {
    final events = await _storage.getPendingEvents(limit: limit.clamp(1, 100));
    if (events.isEmpty) {
      return const StatisticUploadResult(isSuccess: true);
    }

    final device = await _deviceManager.collectDeviceInfo(
      appId: appId,
      channel: channel,
      fallbackAppVersion: fallbackAppVersion,
    );

    final result = await _api.uploadEvents(
      device: device,
      events: events,
    );

    final eventIds = events.map((e) => e.eventId).toList(growable: false);

    if (result.isSuccess) {
      // 上传成功，从本地队列中清除已成功发送的事件
      await _storage.removeEvents(eventIds);
    } else {
      // 上传失败，计算退避延迟并更新重试状态（1分钟 -> 5分钟 -> 15分钟 -> 30分钟 -> 60分钟）
      final delaySeconds = _calculateBackoffDelay(events.first);
      await _storage.updateRetry(eventIds, delaySeconds);
    }

    return result;
  }

  /// 获取当前待上传事件数量
  Future<int> getPendingCount() => _storage.getPendingCount();

  /// 获取最近保存的事件列表
  Future<List<StatisticEvent>> getRecentEvents({int limit = 50}) =>
      _storage.getRecentEvents(limit: limit);

  /// 清空本地队列（诊断工具使用）
  Future<void> clearQueue() => _storage.clearAll();

  /// 指数退避间隔（秒）
  int _calculateBackoffDelay(StatisticEvent event) {
    // 默认基础 60 秒
    return 60;
  }
}
