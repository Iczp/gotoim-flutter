/// 统计配置
class StatisticConfig {
  const StatisticConfig({
    this.enabled = true,
    this.debugLog = true,
    this.batchSize = 20,
    this.maxBatchSize = 100,
    this.uploadInterval = const Duration(seconds: 15),
    this.sessionTimeout = const Duration(minutes: 30),
    this.maxRetryCount = 5,
    this.baseUrl = 'http://10.0.5.20:51621',
    this.appId = '__UNI__39F095D',
    this.channel = const String.fromEnvironment(
      'APP_CHANNEL',
      defaultValue: 'official',
    ),
  });

  /// 是否启用统计采集与上报
  final bool enabled;

  /// 是否在调试控制台输出详细日志
  final bool debugLog;

  /// 建议批量上传条数阈值（达到此数量立即触发上传）
  final int batchSize;

  /// 单次上传最大数量
  final int maxBatchSize;

  /// 定时轮询上传间隔
  final Duration uploadInterval;

  /// Session 后台超时时间（超过此时长重新进入前台创建新 Session）
  final Duration sessionTimeout;

  /// 重试达到此次数后降低重试频率
  final int maxRetryCount;

  /// 统计后台 API 根路径
  final String baseUrl;

  /// 归属 App 标识
  final String appId;

  /// 应用发布渠道
  final String channel;

  StatisticConfig copyWith({
    bool? enabled,
    bool? debugLog,
    int? batchSize,
    int? maxBatchSize,
    Duration? uploadInterval,
    Duration? sessionTimeout,
    int? maxRetryCount,
    String? baseUrl,
    String? appId,
    String? channel,
  }) {
    return StatisticConfig(
      enabled: enabled ?? this.enabled,
      debugLog: debugLog ?? this.debugLog,
      batchSize: batchSize ?? this.batchSize,
      maxBatchSize: maxBatchSize ?? this.maxBatchSize,
      uploadInterval: uploadInterval ?? this.uploadInterval,
      sessionTimeout: sessionTimeout ?? this.sessionTimeout,
      maxRetryCount: maxRetryCount ?? this.maxRetryCount,
      baseUrl: baseUrl ?? this.baseUrl,
      appId: appId ?? this.appId,
      channel: channel ?? this.channel,
    );
  }
}
