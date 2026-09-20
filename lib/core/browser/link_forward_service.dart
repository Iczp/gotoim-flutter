import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/app_navigation.dart';
import '../../features/chat/application/chat_controller.dart';
import '../../features/chat/data/repositories/message_repository.dart';
import '../../features/session/application/session_list_controller.dart';
import '../../features/session/data/models/session_summary.dart';
import '../widgets/app_toast.dart';
import 'recent_forward_service.dart';

/// 网页与链接全局后台转发服务。
///
/// 独立于任何 Widget、页面或弹窗的生命周期。无论触发转发的 BottomSheet、确认弹窗
/// 还是浏览器页面是否已经被 Pop 或销毁，均能在后台独立执行发送任务，
/// 并通过全局独立 Overlay（Toast / Loading）向用户提供反馈。
class LinkForwardService {
  LinkForwardService._();

  /// 全局单例
  static final LinkForwardService instance = LinkForwardService._();

  /// 异步在后台转发链接至一组目标会话。
  ///
  /// - 立即弹出全局 Loading 提示；
  /// - 逐个通过 [MessageRepository.sendLink] 发送链接卡片；
  /// - 若附带 [comment]，紧随其后追加发送附带留言；
  /// - 成功后自动记录目标至 [RecentForwardService]；
  /// - 全部完成后将 Loading 自动切换为成功或失败的 Toast。
  Future<bool> forwardLink({
    required List<SessionSummary> targets,
    required String url,
    String? title,
    String? comment,
    int? fallbackOwnerId,
    MessageRepository? repository,
  }) async {
    if (targets.isEmpty) {
      debugPrint('[LinkForwardService] 转发目标为空，忽略转发');
      return false;
    }

    final container = globalProviderContainer;
    final repo = repository ?? container?.read(messageRepositoryProvider);
    if (repo == null) {
      debugPrint('[LinkForwardService] 无法获取 MessageRepository，全局 Container 未初始化');
      showErrorToast('发送失败: 系统服务未就绪');
      return false;
    }

    final effectiveFallbackOwnerId = fallbackOwnerId ??
        container?.read(sessionListControllerProvider).currentOwnerId ??
        0;

    final count = targets.length;
    debugPrint(
      '[LinkForwardService] 🚀 启动后台链接转发 -> 目标数: $count, '
      'url: $url, title: $title, comment: "${comment ?? ""}"',
    );

    // 弹出全局 Loading 提示
    final dismissLoading = showLoadingToast(
      count > 1 ? '正在转发至 $count 个聊天...' : '正在发送...',
    );

    var successCount = 0;
    var failCount = 0;
    String? lastErrorMsg;

    try {
      for (final target in targets) {
        final effectiveOwnerId = (target.ownerId != null && target.ownerId! > 0)
            ? target.ownerId!
            : effectiveFallbackOwnerId;

        debugPrint(
          '[LinkForwardService] 正在发送至 -> ${target.title} (sessionUnitId: ${target.id}, ownerId: $effectiveOwnerId)',
        );

        try {
          final sentMessage = await repo.sendLink(
            ownerId: effectiveOwnerId,
            sessionUnitId: target.id,
            url: url,
            title: title,
          );

          if (sentMessage.state == 'failed') {
            throw Exception('接口返回失败状态 (state=failed)');
          }

          // 附带留言
          if (comment != null && comment.trim().isNotEmpty) {
            debugPrint(
              '[LinkForwardService] 发送附带留言至 -> ${target.title}: "${comment.trim()}"',
            );
            await repo.sendText(
              ownerId: effectiveOwnerId,
              sessionUnitId: target.id,
              text: comment.trim(),
            );
          }

          // 记录最近转发
          await RecentForwardService.instance.record(target.id);
          successCount++;
          debugPrint(
            '[LinkForwardService] ✅ 成功发送至 -> ${target.title}, msgId: ${sentMessage.localId}',
          );
        } catch (e, st) {
          failCount++;
          lastErrorMsg = e.toString();
          debugPrint(
            '[LinkForwardService] ❌ 发送失败 -> target: ${target.title}(${target.id}): $e\n$st',
          );
        }
      }
    } finally {
      // 关闭 Loading
      dismissLoading();
    }

    debugPrint(
      '[LinkForwardService] 🏁 后台链接转发结束: 成功 $successCount 个, 失败 $failCount 个',
    );

    if (failCount == 0 && successCount > 0) {
      showSuccessToast(count > 1 ? '已全部发送' : '已发送');
      return true;
    } else if (successCount > 0) {
      showWarningToast('部分发送失败 ($failCount/$successCount)');
      return false;
    } else {
      showErrorToast('发送失败: ${lastErrorMsg ?? "网络异常"}');
      return false;
    }
  }
}
