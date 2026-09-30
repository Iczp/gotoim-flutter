import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'statistic_config.dart';
import 'statistic_repository.dart';

/// 统计队列调度器
class StatisticQueue {
  StatisticQueue({
    required StatisticRepository repository,
    required StatisticConfig config,
  })  : _repository = repository,
        _config = config;

  final StatisticRepository _repository;
  StatisticConfig _config;

  Timer? _timer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _uploading = false;
  int _pendingCountCache = 0;

  bool get isUploading => _uploading;
  int get pendingCount => _pendingCountCache;

  void updateConfig(StatisticConfig config) {
    _config = config;
    _restartTimer();
  }

  /// 启动队列调度与监听
  void start() {
    _restartTimer();
    _listenConnectivity();
    // 首次启动刷新待处理计数并尝试上传未完成的队列
    scheduleFlush();
  }

  /// 停止调度
  void stop() {
    _timer?.cancel();
    _timer = null;
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
  }

  /// 记录事件入队后的通知，检查是否满足阈值
  Future<void> onEventEnqueued() async {
    _pendingCountCache++;
    if (_pendingCountCache >= _config.batchSize) {
      scheduleFlush();
    }
  }

  /// 调度上传任务（单任务并发控制）
  Future<void> scheduleFlush() async {
    if (!_config.enabled || _uploading) return;
    _uploading = true;

    try {
      final pending = await _repository.getPendingCount();
      _pendingCountCache = pending;

      if (pending > 0) {
        if (_config.debugLog) {
          debugPrint('[Statistic] trigger upload, pending events: $pending');
        }

        final result = await _repository.uploadPendingBatch(
          appId: _config.appId,
          channel: _config.channel,
          limit: _config.maxBatchSize,
        );

        if (_config.debugLog) {
          if (result.isSuccess) {
            debugPrint(
              '[Statistic] upload success: sent ${result.receivedCount}, new ${result.successCount}, dup ${result.duplicateCount}',
            );
          } else {
            debugPrint(
              '[Statistic] upload failed (will retry): ${result.errorMessage}',
            );
          }
        }

        _pendingCountCache = await _repository.getPendingCount();

        // 如果还有剩余超过 batchSize 的事件，继续触发下一批上传
        if (result.isSuccess && _pendingCountCache >= _config.batchSize) {
          Future.microtask(scheduleFlush);
        }
      }
    } catch (e, st) {
      if (_config.debugLog) {
        debugPrint('[Statistic] upload queue unexpected error: $e\n$st');
      }
    } finally {
      _uploading = false;
    }
  }

  void _restartTimer() {
    _timer?.cancel();
    if (!_config.enabled) return;
    _timer = Timer.periodic(_config.uploadInterval, (_) {
      scheduleFlush();
    });
  }

  void _listenConnectivity() {
    _connectivitySubscription?.cancel();
    try {
      _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
        (results) {
          final hasConnection = results.any(
            (r) => r != ConnectivityResult.none,
          );
          if (hasConnection) {
            if (_config.debugLog) {
              debugPrint('[Statistic] network recovered, trigger upload');
            }
            scheduleFlush();
          }
        },
      );
    } catch (_) {}
  }
}
