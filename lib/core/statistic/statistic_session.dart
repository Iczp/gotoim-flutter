import 'package:uuid/uuid.dart';

/// 统计会话 (Session) 管理器
class StatisticSessionManager {
  StatisticSessionManager();

  String _sessionId = const Uuid().v4();
  DateTime _sessionStartTime = DateTime.now();
  DateTime _lastActiveTime = DateTime.now();
  DateTime? _backgroundTime;

  String get currentSessionId => _sessionId;
  DateTime get sessionStartTime => _sessionStartTime;
  DateTime get lastActiveTime => _lastActiveTime;
  DateTime? get backgroundTime => _backgroundTime;

  /// 开始全新会话（冷启动或超时后）
  String startNewSession() {
    _sessionId = const Uuid().v4();
    _sessionStartTime = DateTime.now();
    _lastActiveTime = _sessionStartTime;
    _backgroundTime = null;
    return _sessionId;
  }

  /// 更新活跃时间
  void markActive() {
    _lastActiveTime = DateTime.now();
  }

  /// App 进入后台
  void onAppBackground([DateTime? now]) {
    final time = now ?? DateTime.now();
    _backgroundTime = time;
    _lastActiveTime = time;
  }

  /// App 恢复前台，根据超时时长判断是否需要更新 Session
  /// 返回 true 表示开启了新 Session，false 表示沿用当前 Session
  bool onAppForeground(Duration sessionTimeout, [DateTime? now]) {
    markActive();
    if (_backgroundTime != null) {
      final currentTime = now ?? DateTime.now();
      final elapsed = currentTime.difference(_backgroundTime!);
      _backgroundTime = null;
      if (elapsed >= sessionTimeout) {
        startNewSession();
        return true;
      }
    }
    return false;
  }
}
