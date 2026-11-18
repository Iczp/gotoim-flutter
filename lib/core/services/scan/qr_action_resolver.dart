import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../deep_link/deep_link_service.dart';
import '../../deep_link/deep_link_target.dart';
import '../../../features/qr_code/data/qr_code_repository.dart';
import '../../../features/qr_code/presentation/qr_code_card_modal.dart';
import '../../../features/scan_login/application/scan_login_controller.dart';
import '../../../features/session/application/session_list_controller.dart';
import 'scan_code_models.dart';
import 'unified_scan_dispatcher.dart';

/// 二维码识别出的语义动作类型
enum QrActionType {
  /// 用户名片 / 个人主页
  user,

  /// 群聊二维码 / 邀请入群
  group,

  /// 扫码登录授权
  scanLogin,

  /// 外部 HTTP / HTTPS 链接
  webUrl,

  /// 普通文本或通用二维码
  plainText,
}

/// 解析后的强类型二维码动作实体
class QrParsedAction {
  const QrParsedAction({
    required this.type,
    required this.rawText,
    required this.title,
    required this.icon,
    required this.onExecute,
  });

  final QrActionType type;
  final String rawText;
  final String title;
  final IconData icon;
  final Future<void> Function(BuildContext context, WidgetRef ref) onExecute;
}

/// 二维码内容语义解析器
class QrActionResolver {
  const QrActionResolver();

  /// 对已知文本分析语义，并构造可在菜单中直接展现和点击直达的动作模型
  static Future<QrParsedAction?> resolve({
    required WidgetRef ref,
    required String rawText,
  }) async {
    final text = rawText.trim();
    if (text.isEmpty) return null;

    // 0. 优先通过服务端 /api/chat/qr-code/resolve 识别系统二维码（名片、群邀请、短链与历史协议）
    if (QrCodeRepository.isPotentialSystemQr(text)) {
      try {
        final currentOwnerId = ref.read(sessionListControllerProvider).currentOwnerId;
        final resolved = await ref.read(qrCodeRepositoryProvider).resolve(
              text,
              currentChatObjectId: currentOwnerId,
            );
        if (resolved != null && (resolved.isCardOrGroup || resolved.qrCodeId != null)) {
          final labelName = resolved.ownerName?.isNotEmpty == true
              ? resolved.ownerName!
              : (resolved.isGroup ? '群聊' : '名片');
          final actionTitle = !resolved.isValid
              ? '查看失效${resolved.isGroup ? '群' : ''}名片'
              : resolved.isGroup
              ? '识别图中群聊：$labelName'
              : '识别图中名片：$labelName';

          return QrParsedAction(
            type: resolved.isGroup ? QrActionType.group : QrActionType.user,
            rawText: text,
            title: actionTitle,
            icon: resolved.isGroup
                ? Icons.group_outlined
                : Icons.contact_page_outlined,
            onExecute: (context, ref) async {
              if (!context.mounted) return;
              await QrCodeCardModal.show(
                context,
                data: resolved,
                rawContent: text,
              );
            },
          );
        }
      } catch (_) {}
    }

    final uri = Uri.tryParse(text);

    // 1. 深度链接 (gotoim:// 或 gotoim-dev://)
    if (uri != null && (uri.scheme == 'gotoim' || uri.scheme == 'gotoim-dev')) {
      final deepLinkService = ref.read(deepLinkServiceProvider);
      final parseResult = deepLinkService.parser.parse(uri);
      final target = parseResult.target;

      if (target is UserDeepLink) {
        return QrParsedAction(
          type: QrActionType.user,
          rawText: text,
          title: '识别图中用户资料',
          icon: Icons.person_pin_outlined,
          onExecute: (context, ref) async {
            await deepLinkService.handleUri(uri, source: 'image_qr');
          },
        );
      }

      if (target is GroupDeepLink || target is GroupInviteDeepLink) {
        return QrParsedAction(
          type: QrActionType.group,
          rawText: text,
          title: '识别图中群聊',
          icon: Icons.group_outlined,
          onExecute: (context, ref) async {
            await deepLinkService.handleUri(uri, source: 'image_qr');
          },
        );
      }

      if (target is ScanLoginDeepLink) {
        return QrParsedAction(
          type: QrActionType.scanLogin,
          rawText: text,
          title: '前往扫码登录',
          icon: Icons.qr_code_scanner_rounded,
          onExecute: (context, ref) async {
            await deepLinkService.handleUri(uri, source: 'image_qr');
          },
        );
      }
    }

    // 2. 检查是否为扫码登录特征文本 (通过 scanLoginRepositoryProvider)
    try {
      final scanLoginRepo = ref.read(scanLoginRepositoryProvider);
      final loginScanText = await scanLoginRepo.resolveLoginScan(text);
      if (loginScanText != null) {
        return QrParsedAction(
          type: QrActionType.scanLogin,
          rawText: text,
          title: '前往扫码登录',
          icon: Icons.qr_code_scanner_rounded,
          onExecute: (context, ref) async {
            if (context.mounted) {
              context.push(
                '/scan-login?scanText=${Uri.encodeQueryComponent(loginScanText)}',
              );
            }
          },
        );
      }
    } catch (_) {}

    // 3. 检查是否为 HTTP / HTTPS 链接
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      // 包含 scanText query 的登录链接
      if (uri.queryParameters.containsKey('scanText')) {
        final scanText = uri.queryParameters['scanText']!;
        return QrParsedAction(
          type: QrActionType.scanLogin,
          rawText: text,
          title: '前往扫码登录',
          icon: Icons.qr_code_scanner_rounded,
          onExecute: (context, ref) async {
            if (context.mounted) {
              context.push(
                '/scan-login?scanText=${Uri.encodeQueryComponent(scanText)}',
              );
            }
          },
        );
      }

      return QrParsedAction(
        type: QrActionType.webUrl,
        rawText: text,
        title: '打开图中的网址',
        icon: Icons.language_rounded,
        onExecute: (context, ref) async {
          final dispatcher = ref.read(unifiedScanDispatcherProvider);
          await dispatcher.dispatchResult(
            context,
            ref,
            ScanCodeResult(
              content: text,
              format: ScanCodeFormat.qrCode,
              source: ScanCodeSource.album,
            ),
          );
        },
      );
    }

    // 4. 兜底纯文本 / 通用二维码
    return QrParsedAction(
      type: QrActionType.plainText,
      rawText: text,
      title: '识别图中的二维码',
      icon: Icons.qr_code_2_rounded,
      onExecute: (context, ref) async {
        final dispatcher = ref.read(unifiedScanDispatcherProvider);
        await dispatcher.dispatchResult(
          context,
          ref,
          ScanCodeResult(
            content: text,
            format: ScanCodeFormat.qrCode,
            source: ScanCodeSource.album,
          ),
        );
      },
    );
  }
}
