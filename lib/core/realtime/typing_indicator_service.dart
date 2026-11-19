import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../features/chat/data/datasources/message_api.dart';
import 'signalr_gateway.dart';

class _TypingMemberEntry {
  _TypingMemberEntry({
    required this.name,
    this.action = 'typing',
    this.actionText,
    required this.timer,
  });

  String name;
  String action;
  String? actionText;
  Timer timer;
}

/// 瞬态“正在输入/录音/发文件”状态管理器（不落库，内存维护 + 超时自动清理）。
class TypingIndicatorService extends ChangeNotifier {
  static const Duration _expireDuration = Duration(milliseconds: 6000);
  static const Duration _throttleDuration = Duration(milliseconds: 2500);

  final Map<String, Map<String, _TypingMemberEntry>> _typingMap = {};
  final Map<String, _ReportState> _lastReportState = {};

  void handleTypingEvent(SignalRTypingEvent event, {String? mySessionUnitId}) {
    if (event.sessionId.isEmpty || event.senderSessionUnitId.isEmpty) return;
    if (mySessionUnitId != null && event.senderSessionUnitId == mySessionUnitId) {
      return;
    }

    if (event.isTyping) {
      _setMemberTyping(
        event.sessionId,
        event.senderSessionUnitId,
        event.senderName,
        action: event.action,
        actionText: event.actionText,
      );
    } else {
      clearMemberTyping(event.sessionId, event.senderSessionUnitId);
    }
  }

  void _setMemberTyping(
    String sessionId,
    String senderUnitId,
    String senderName, {
    String action = 'typing',
    String? actionText,
  }) {
    final sessionMap = _typingMap.putIfAbsent(sessionId, () => {});
    sessionMap[senderUnitId]?.timer.cancel();
    final timer = Timer(_expireDuration, () {
      clearMemberTyping(sessionId, senderUnitId);
    });
    sessionMap[senderUnitId] = _TypingMemberEntry(
      name: senderName,
      action: action,
      actionText: actionText,
      timer: timer,
    );
    notifyListeners();
  }

  /// 收到新消息或对方停止操作时立即清除
  void clearMemberTyping(String sessionId, String senderUnitId) {
    final sessionMap = _typingMap[sessionId];
    if (sessionMap == null) return;
    final entry = sessionMap.remove(senderUnitId);
    if (entry != null) {
      entry.timer.cancel();
      if (sessionMap.isEmpty) {
        _typingMap.remove(sessionId);
      }
      notifyListeners();
    }
  }

  /// 收到该会话的任意新消息时整体清除
  void clearSession(String sessionId) {
    final sessionMap = _typingMap.remove(sessionId);
    if (sessionMap != null) {
      for (final entry in sessionMap.values) {
        entry.timer.cancel();
      }
      notifyListeners();
    }
  }

  static String _getActionLabel(String action, String? actionText) {
    if (actionText != null && actionText.trim().isNotEmpty) {
      return actionText.trim();
    }
    switch (action) {
      case 'recording_voice':
        return '正在录音...';
      case 'uploading_image':
        return '正在发送图片...';
      case 'uploading_video':
        return '正在发送视频...';
      case 'uploading_file':
        return '正在发送文件...';
      case 'typing':
      default:
        return '正在输入...';
    }
  }

  /// 自适应返回展示文案（私聊/群聊通用）
  String getTypingText(String sessionId, {bool isDirect = false}) {
    final sessionMap = _typingMap[sessionId];
    if (sessionMap == null || sessionMap.isEmpty) return '';
    final members = sessionMap.values.toList();
    if (members.length == 1) {
      final m = members.first;
      final label = _getActionLabel(m.action, m.actionText);
      return isDirect ? '对方$label' : '${m.name} $label';
    }
    final first = members.first;
    return '${first.name} 等 ${members.length} 人正在输入...';
  }

  /// 带 2.5 秒节流上报输入状态（优先通过 REST API，如不可用降级 SignalR invoke）
  Future<void> reportTyping({
    MessageApi? messageApi,
    SignalRGateway? gateway,
    required String sessionId,
    required String senderSessionUnitId,
    required String senderName,
    required bool isTyping,
    String action = 'typing',
    String? actionText,
  }) async {
    if (sessionId.isEmpty || senderSessionUnitId.isEmpty) return;
    final now = DateTime.now();
    final last = _lastReportState[sessionId];
    if (isTyping) {
      if (last != null &&
          last.action == action &&
          now.difference(last.time) < _throttleDuration) {
        return;
      }
      _lastReportState[sessionId] = _ReportState(time: now, action: action);
    } else {
      _lastReportState.remove(sessionId);
    }

    if (messageApi != null) {
      await messageApi.sendTyping(
        sessionUnitId: senderSessionUnitId,
        sessionId: sessionId,
        senderName: senderName,
        isTyping: isTyping,
        action: action,
        actionText: actionText,
      );
      return;
    }

    if (gateway != null) {
      try {
        await gateway.invoke<void>(
          'SendTypingAsync',
          arguments: <Object>[
            sessionId,
            senderSessionUnitId,
            senderName.isEmpty ? '我' : senderName,
            isTyping,
          ],
        );
      } catch (_) {
        // 忽略
      }
    }
  }

  @override
  void dispose() {
    for (final sessionMap in _typingMap.values) {
      for (final entry in sessionMap.values) {
        entry.timer.cancel();
      }
    }
    _typingMap.clear();
    super.dispose();
  }
}

class _ReportState {
  _ReportState({required this.time, required this.action});
  final DateTime time;
  final String action;
}
