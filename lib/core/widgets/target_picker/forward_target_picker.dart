import 'package:flutter/material.dart';

import '../../../features/session/data/models/session_summary.dart';
import 'target_picker.dart';

/// 统一封装的转发/分享目标选择器门面。
///
/// **核心职责原则**：
/// - 单独封装，彻底解耦。
/// - **仅负责展示会话列表/搜索、由用户勾选并返回选中的 `List<SessionSummary>?`**。
/// - **绝不直接执行发送、转发或网络请求**。
/// - 选中的结果由调用方（如聊天页面执行消息转发、网页浏览器执行发送链接卡片等）各自处理。
abstract final class ForwardTargetPicker {
  /// 唤起转发目标选择器，返回用户选中的会话列表。
  ///
  /// - 若用户点击取消或返回，返回 `null`。
  /// - [sessions]：可选的预加载候选会话列表。若提供了 [sessionLoader]，在未传入 [sessions] 时会异步加载。
  /// - [excludeSessionUnitId]：排除的当前会话 ID（例如不转发给自己当前正在聊天的会话）。
  /// - [multiple]：是否支持多选，默认为 `false`（单选直接点击返回）。
  /// - [maxCount]：多选时的最大可选数量（默认 9 个）。
  static Future<List<SessionSummary>?> pickTargets({
    required BuildContext context,
    List<SessionSummary>? sessions,
    Future<List<SessionSummary>> Function()? sessionLoader,
    String title = '选择转发目标',
    String? subtitle,
    bool multiple = false,
    int? maxCount = 9,
    int? minCount = 1,
    String? excludeSessionUnitId,
    Set<String> disabledIds = const <String>{},
    bool enableSearch = true,
  }) async {
    var candidateSessions = sessions;
    if (candidateSessions == null && sessionLoader != null) {
      candidateSessions = await sessionLoader();
    }
    candidateSessions ??= const <SessionSummary>[];

    if (excludeSessionUnitId != null && excludeSessionUnitId.isNotEmpty) {
      candidateSessions = candidateSessions
          .where((s) => s.id != excludeSessionUnitId)
          .toList(growable: false);
    }

    if (candidateSessions.isEmpty || !context.mounted) {
      return null;
    }

    return TargetPicker.pickSessionUnits(
      context: context,
      sessions: candidateSessions,
      title: title,
      subtitle: subtitle,
      multiple: multiple,
      showConfirmButton: multiple ? true : false,
      maxCount: multiple ? maxCount : 1,
      minCount: minCount,
      disabledIds: disabledIds,
    );
  }

  /// 单选模式快捷方法，直接返回选中的单个 [SessionSummary]，若未选返回 `null`。
  static Future<SessionSummary?> pickSingleTarget({
    required BuildContext context,
    List<SessionSummary>? sessions,
    Future<List<SessionSummary>> Function()? sessionLoader,
    String title = '选择发送给谁',
    String? subtitle,
    String? excludeSessionUnitId,
    Set<String> disabledIds = const <String>{},
    bool enableSearch = true,
  }) async {
    final list = await pickTargets(
      context: context,
      sessions: sessions,
      sessionLoader: sessionLoader,
      title: title,
      subtitle: subtitle,
      multiple: false,
      excludeSessionUnitId: excludeSessionUnitId,
      disabledIds: disabledIds,
      enableSearch: enableSearch,
    );
    if (list != null && list.isNotEmpty) {
      return list.first;
    }
    return null;
  }
}
