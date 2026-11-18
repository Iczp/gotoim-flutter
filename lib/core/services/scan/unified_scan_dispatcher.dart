import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../deep_link/deep_link_service.dart';
import '../../widgets/app_modal.dart';
import '../../widgets/app_toast.dart';
import '../../../features/qr_code/data/qr_code_repository.dart';
import '../../../features/qr_code/presentation/qr_code_card_modal.dart';
import '../../../features/scan_login/application/scan_login_controller.dart';
import '../../../features/session/application/session_list_controller.dart';
import 'scan_code_service.dart';

/// 统一扫码业务调度器
/// 负责唤起相机/相册统一扫码器，并根据扫描文本类型（登录码、好友/群深度链接、外部链接、普通条码/文本）自动分发执行。
class UnifiedScanDispatcher {
  const UnifiedScanDispatcher();

  /// 唤起扫码并自动分发执行。
  Future<void> openAndDispatch(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final scanService = ref.read(scanCodeServiceProvider);

    final result = await scanService.scanCode(
      navigator,
      const ScanCodeRequest(
        title: '扫一扫',
        tip: '将二维码或条形码放入框内，即可自动扫描',
      ),
    );

    if (result == null || !context.mounted) return;
    await dispatchResult(context, ref, result);
  }

  /// 针对已知扫描结果执行智能分发。
  Future<void> dispatchResult(
    BuildContext context,
    WidgetRef ref,
    ScanCodeResult result,
  ) async {
    final raw = result.content.trim();
    if (raw.isEmpty) return;

    // 1. 优先尝试作为扫码登录解析
    final scanLoginRepo = ref.read(scanLoginRepositoryProvider);
    try {
      final loginScanText = await scanLoginRepo.resolveLoginScan(
        raw,
        scanType: result.format?.apiValue,
      );
      if (loginScanText != null && context.mounted) {
        context.push(
          '/scan-login?scanText=${Uri.encodeQueryComponent(loginScanText)}',
        );
        return;
      }
    } catch (_) {
      // 忽略登录解析非关键失败，继续向下分发
    }

    // 2. 尝试通过服务端 /api/chat/qr-code/resolve 或 /api/chat/scan-code/scan 识别系统名片/群码
    final currentOwnerId = ref.read(sessionListControllerProvider).currentOwnerId;
    final qrRepo = ref.read(qrCodeRepositoryProvider);
    if (QrCodeRepository.isPotentialSystemQr(raw)) {
      final resolved = await qrRepo.resolve(
        raw,
        currentChatObjectId: currentOwnerId,
      );
      if (resolved != null &&
          (resolved.isCardOrGroup || resolved.qrCodeId != null) &&
          context.mounted) {
        await QrCodeCardModal.show(context, data: resolved, rawContent: raw);
        return;
      }
    } else {
      final scanRes = await qrRepo.scanCode(
        type: result.format?.apiValue ?? 'QR_CODE',
        content: raw,
        currentChatObjectId: currentOwnerId,
      );
      if (scanRes != null && context.mounted) {
        for (final handler in scanRes.scanHandlers) {
          if (handler.success &&
              (handler.action == 'chat_object_card' ||
                  handler.action == 'group_invite')) {
            final resolved = await qrRepo.resolve(
              raw,
              currentChatObjectId: currentOwnerId,
            );
            if (resolved != null && context.mounted) {
              await QrCodeCardModal.show(
                context,
                data: resolved,
                rawContent: raw,
              );
              return;
            }
          }
        }
      }
    }

    // 3. 检查是否为 gotoim-dev:// 或 gotoim:// 深度链接
    final uri = Uri.tryParse(raw);
    if (uri != null &&
        (uri.scheme == 'gotoim-dev' || uri.scheme == 'gotoim')) {
      final deepLinkService = ref.read(deepLinkServiceProvider);
      final dlResult = await deepLinkService.handleUri(
        uri,
        source: 'scan_code',
      );
      if (context.mounted && !dlResult.isSuccess) {
        showToast(dlResult.message, type: ToastType.warning);
      }
      return;
    }

    // 3. 检查是否为 HTTP / HTTPS 链接
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      // 若是包含扫码登录 query 的特定链接
      if (uri.queryParameters.containsKey('scanText') && context.mounted) {
        final scanText = uri.queryParameters['scanText']!;
        context.push(
          '/scan-login?scanText=${Uri.encodeQueryComponent(scanText)}',
        );
        return;
      }

      if (context.mounted) {
        final confirmed = await showConfirmModal(
          context: context,
          title: '识别到网址',
          message: '$raw\n\n是否复制链接并在外部浏览器中访问？',
          confirmText: '复制链接',
        );
        if (confirmed && context.mounted) {
          await Clipboard.setData(ClipboardData(text: raw));
          showToast('链接已复制到剪贴板', type: ToastType.success);
        }
      }
      return;
    }

    // 4. 普通条形码或文本内容 -> 弹出内容展示对话框，支持一键复制
    if (context.mounted) {
      await showModalDialog<void>(
        context: context,
        title: '扫码结果',
        content: raw,
        confirmText: '复制内容',
        showCancel: true,
        cancelText: '关闭',
        onConfirm: (_) async {
          await Clipboard.setData(ClipboardData(text: raw));
          showToast('已复制到剪贴板', type: ToastType.success);
          return true;
        },
      );
    }
  }
}

final unifiedScanDispatcherProvider = Provider<UnifiedScanDispatcher>(
  (ref) => const UnifiedScanDispatcher(),
);
