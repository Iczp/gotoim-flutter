import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../database/unified_database.dart';
import '../network/token_storage.dart';
import 'statistic_api.dart';
import 'statistic_config.dart';
import 'statistic_device.dart';
import 'statistic_event.dart';
import 'statistic_event_names.dart';
import 'statistic_queue.dart';
import 'statistic_repository.dart';
import 'statistic_session.dart';
import 'statistic_storage.dart';

/// 统一统计服务单例
class StatisticService with WidgetsBindingObserver {
  StatisticService._();

  static final StatisticService instance = StatisticService._();

  StatisticConfig _config = const StatisticConfig();
  late final StatisticDeviceManager _deviceManager = StatisticDeviceManager();
  late final StatisticSessionManager _sessionManager = StatisticSessionManager();
  StatisticStorage? _storage;
  StatisticApi? _api;
  StatisticRepository? _repository;
  StatisticQueue? _queue;

  bool _isInitialized = false;
  String? _currentUserId;

  bool get isInitialized => _isInitialized;
  StatisticConfig get config => _config;
  String? get currentUserId => _currentUserId;
  String get currentSessionId => _sessionManager.currentSessionId;
  String? get currentDeviceKey => _deviceManager.currentDeviceKey;
  StatisticDeviceInfo? get currentDeviceInfo => _deviceManager.currentDeviceInfo;
  StatisticQueue? get queue => _queue;
  StatisticRepository? get repository => _repository;

  /// 初始化统计服务
  ///
  /// 在 [main] 或 [bootstrap] 中调用：
  /// ```dart
  /// await StatisticService.instance.initialize(
  ///   database: database,
  ///   config: StatisticConfig(...),
  /// );
  /// ```
  Future<void> initialize({
    required UnifiedDatabase database,
    StatisticConfig? config,
    TokenStorage? tokenStorage,
    StatisticApi? customApi,
  }) async {
    if (_isInitialized) return;

    if (config != null) {
      _config = config;
    }

    try {
      _storage = DatabaseStatisticStorage(database);
      _api = customApi ??
          DioStatisticApi(
            baseUrl: _config.baseUrl,
            tokenStorage: tokenStorage,
          );
      _repository = StatisticRepository(
        storage: _storage!,
        api: _api!,
        deviceManager: _deviceManager,
      );
      _queue = StatisticQueue(
        repository: _repository!,
        config: _config,
      );

      // 1. 初始化并读取 DeviceKey、设备信息
      await _deviceManager.collectDeviceInfo(
        appId: _config.appId,
        channel: _config.channel,
      );

      // 2. 创建初始 Session
      _sessionManager.startNewSession();

      // 3. 注册生命周期监听
      WidgetsBinding.instance.addObserver(this);

      // 4. 注册全局未捕获异常监听 (Crash)
      _setupCrashHandler();

      // 5. 记录 app_start 事件
      await track(
        StatisticEventNames.appStart,
        properties: <String, dynamic>{
          'coldStart': true,
        },
      );

      // 6. 启动上传任务
      _queue?.start();

      _isInitialized = true;

      if (_config.debugLog) {
        debugPrint(
          '[Statistic] initialized successfully, deviceKey=${_deviceManager.currentDeviceKey}, sessionId=$currentSessionId',
        );
      }
    } catch (e, st) {
      debugPrint('[Statistic] initialization failed: $e\n$st');
      // 保证不影响主程序启动
    }
  }

  /// 绑定当前登录用户标识
  void setUser(String userId) {
    _currentUserId = userId;
    if (_config.debugLog) {
      debugPrint('[Statistic] set user: $userId');
    }
  }

  /// 清除当前用户标识
  void clearUser() {
    _currentUserId = null;
    if (_config.debugLog) {
      debugPrint('[Statistic] clear user');
    }
  }

  /// 上报记录业务或系统事件
  Future<void> track(
    String eventName, {
    String? page,
    Map<String, dynamic>? properties,
  }) async {
    if (!_config.enabled) return;

    try {
      _sessionManager.markActive();

      final event = StatisticEvent(
        eventName: eventName,
        sessionId: _sessionManager.currentSessionId,
        page: page,
        eventTime: DateTime.now(),
        properties: properties,
      );

      if (_config.debugLog) {
        debugPrint(
          '[Statistic] track: ${event.eventName}, page: ${event.page}, session: ${event.sessionId}',
        );
      }

      await _storage?.enqueue(event);
      await _queue?.onEventEnqueued();
    } catch (e) {
      if (_config.debugLog) {
        debugPrint('[Statistic] track error: $e');
      }
    }
  }

  /// 立即触发上传当前所有队列
  Future<void> flush() async {
    if (!_config.enabled) return;
    await _queue?.scheduleFlush();
  }

  /// 动态更新配置（例如在诊断中心修改参数）
  void updateConfig(StatisticConfig newConfig) {
    _config = newConfig;
    _queue?.updateConfig(newConfig);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isInitialized || !_config.enabled) return;

    switch (state) {
      case AppLifecycleState.resumed:
        final isNewSession =
            _sessionManager.onAppForeground(_config.sessionTimeout);
        track(
          StatisticEventNames.appForeground,
          properties: <String, dynamic>{
            'isNewSession': isNewSession,
          },
        );
        break;

      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _sessionManager.onAppBackground();
        track(StatisticEventNames.appBackground);
        // 切后台时立即执行一次持久化上传
        flush();
        break;

      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _sessionManager.onAppBackground();
        break;
    }
  }

  void _setupCrashHandler() {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      originalOnError?.call(details);

      track(
        StatisticEventNames.crash,
        properties: <String, dynamic>{
          'errorType': details.exception.runtimeType.toString(),
          'message': details.exceptionAsString(),
          'stack': details.stack?.toString().split('\n').take(10).join('\n'),
        },
      );
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      track(
        StatisticEventNames.crash,
        properties: <String, dynamic>{
          'errorType': error.runtimeType.toString(),
          'message': error.toString(),
          'stack': stack.toString().split('\n').take(10).join('\n'),
        },
      );
      return false;
    };
  }
}
