import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../features/session/data/models/session_summary.dart';

/// 最近转发会话记录服务。
///
/// 维护用户最近转发或分享过的会话列表，用于在网页更多面板、消息转发列表等场景置顶展示。
class RecentForwardService {
  RecentForwardService._({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();
  static final RecentForwardService instance = RecentForwardService._();

  static const String _prefKey = 'gotoim_recent_forward_session_unit_ids';
  final FlutterSecureStorage _storage;
  final List<String> _recentIds = <String>[];
  bool _initialized = false;

  /// 初始化并从本地持久化加载历史记录。
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final raw = await _storage.read(key: _prefKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _recentIds.clear();
          _recentIds.addAll(decoded.whereType<String>());
        }
      }
    } catch (e) {
      debugPrint('[RecentForwardService] init error: $e');
    }
  }

  /// 记录一次转发目标。
  Future<void> record(String sessionUnitId) async {
    if (sessionUnitId.isEmpty) return;
    _recentIds.remove(sessionUnitId);
    _recentIds.insert(0, sessionUnitId);
    if (_recentIds.length > 20) {
      _recentIds.removeRange(20, _recentIds.length);
    }
    try {
      await _storage.write(key: _prefKey, value: jsonEncode(_recentIds));
    } catch (e) {
      debugPrint('[RecentForwardService] save error: $e');
    }
  }

  /// 获取最近转发目标列表。
  ///
  /// - 优先返回有明确转发记录的会话；
  /// - 若历史记录不足 [limit] 个，自动从 [allSessions] 中按活跃顺序补齐；
  /// - 自动去重。
  List<SessionSummary> getRecentTargets({
    required List<SessionSummary> allSessions,
    int limit = 8,
  }) {
    if (allSessions.isEmpty) return const <SessionSummary>[];

    final sessionMap = <String, SessionSummary>{
      for (final s in allSessions) s.id: s,
    };

    final result = <SessionSummary>[];
    final addedIds = <String>{};

    // 1. 优先放入有历史转发记录的会话
    for (final id in _recentIds) {
      final session = sessionMap[id];
      if (session != null && !addedIds.contains(session.id)) {
        result.add(session);
        addedIds.add(session.id);
        if (result.length >= limit) break;
      }
    }

    // 2. 补齐活跃会话（例如文件传输助手、最近联系人）
    if (result.length < limit) {
      for (final session in allSessions) {
        if (!addedIds.contains(session.id)) {
          result.add(session);
          addedIds.add(session.id);
          if (result.length >= limit) break;
        }
      }
    }

    return result;
  }
}
