import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_navigation.dart';
import '../browser/app_webview_page.dart';
import '../browser/desktop_browser_window.dart';
import '../config/app_environment.dart';
import '../native/native.dart';
import '../widgets/app_modal.dart';
import '../widgets/app_toast.dart';
import 'pages/url_interstitial_page.dart';
import 'url_security_level.dart';
import 'url_security_repository.dart';
import 'widgets/url_risk_dialog.dart';

/// URL 安全调度服务（提供应用内统一的 URL 点击分发、安全合规阻断与中转提示）
class UrlSecurityService {
  UrlSecurityService({required UrlSecurityRepository repository})
    : _repository = repository;

  final UrlSecurityRepository _repository;
  static UrlSecurityService? _fallbackInstance;

  /// 全局单例便捷访问
  static UrlSecurityService get instance {
    final container = globalProviderContainer;
    if (container != null) {
      return container.read(urlSecurityServiceProvider);
    }
    return _fallbackInstance ??= UrlSecurityService(
      repository: DefaultUrlSecurityRepository(
        environment: AppEnvironment.defaultEnvironment,
      ),
    );
  }

  /// 快速检测给定 URL 域名是否属于官方或受信白名单（用于 WebView 隔离特权 JSBridge）
  bool isTrustedDomain(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) return false;
    try {
      final uri = Uri.parse(rawUrl.trim());
      if (uri.host.isEmpty) return false;
      final host = uri.host.toLowerCase();
      final trusted = _repository.trustedHosts;
      for (final t in trusted) {
        if (host == t || host.endsWith('.$t')) return true;
      }
    } catch (_) {}
    return false;
  }

  /// 检测是否是危险可执行安装包下载链接
  bool isDangerousDownload(String? rawUrl) {
    if (rawUrl == null) return false;
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return false;
    final path = Uri.decodeComponent(uri.path).toLowerCase();
    return const [
      '.apk',
      '.exe',
      '.dmg',
      '.bat',
      '.cmd',
      '.sh',
      '.msi',
      '.ipa',
      '.scr',
      '.com',
      '.ps1',
    ].any(path.endsWith);
  }

  /// 评估 URL 安全等级
  Future<UrlSecurityCheckResult> checkUrl(String url) {
    // Fail visibly instead of leaving a tab waiting indefinitely. Timeout
    // never grants access; the browser keeps its navigation gate closed.
    return _repository.checkUrl(url).timeout(const Duration(seconds: 5));
  }

  /// 桌面端强力阻断拦截对话框
  static Future<void> showDesktopBlockedDialog(
    BuildContext context, {
    required UrlSecurityCheckResult checkResult,
  }) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.gpp_bad_rounded,
                    color: Colors.red,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  '已停止访问该网页',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '该网址已被安全风控系统强力拦截：',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SelectableText(
                    checkResult.url,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                if ((checkResult.interceptReason != null &&
                        checkResult.interceptReason!.isNotEmpty) ||
                    checkResult.message.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    '拦截原因：${checkResult.interceptReason ?? checkResult.message}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.redAccent,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: checkResult.url));
                  showToast('链接已复制', type: ToastType.success);
                },
                child: const Text('复制链接'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('我知道了'),
              ),
            ],
          ),
    );
  }

  /// 应用内统一打开 URL 入口（集成三阶段防护逻辑：白名单直接打开、未知第三方显示风险中转页/警示弹窗、黑名单强阻断）
  ///
  /// - [useInterstitialPage]: 是否优先使用微信同款全屏中转页（默认 true，若为 false 则展示弹窗）；
  Future<void> openUrl(
    BuildContext context, {
    required String url,
    String? title,
    String? fallbackContent,
    bool useInterstitialPage = true,
  }) async {
    var trimmed = url.trim();
    if (trimmed.isEmpty) return;

    // 1. 处理特定非网页 Scheme (tel:)
    if (trimmed.toLowerCase().startsWith('tel:')) {
      final phone = trimmed.substring(4);
      final confirmed = await showConfirmModal(
        context: context,
        title: '拨打电话',
        message: '是否呼叫 $phone？',
        confirmText: '呼叫',
      );
      if (confirmed) {
        await Native.makePhoneCall(phone);
      }
      return;
    }

    final isDesktop =
        !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    final normalizedUrl = DesktopBrowserWindow.validateAndNormalizeUrl(trimmed);

    // 桌面端统一由 DesktopBrowserWindow 接管格式校验、白名单/黑名单风控拦截与加载渲染
    if (isDesktop) {
      await AppWebViewPage.open(
        context,
        url: normalizedUrl ?? trimmed,
        title: title,
        fallbackContent: fallbackContent,
      );
      return;
    }

    // 2. 移动端：检查是否为标准 HTTP/HTTPS 协议
    if (normalizedUrl == null) {
      await Clipboard.setData(ClipboardData(text: trimmed));
      if (context.mounted) {
        showToast('已复制外部协议链接：$trimmed', type: ToastType.info);
      }
      return;
    }
    trimmed = normalizedUrl;

    // 3. 移动端：执行 URL 安全与风控判定
    final checkResult = await _repository.checkUrl(trimmed);

    if (!context.mounted) return;

    // 4. 根据安全等级分流处理
    switch (checkResult.level) {
      case UrlSecurityLevel.safe:
        // 官方/受信白名单：直接进入内置安全浏览器
        await AppWebViewPage.open(
          context,
          url: trimmed,
          title: title,
          fallbackContent: fallbackContent,
        );
        return;

      case UrlSecurityLevel.blocked:
        // 黑名单/违规欺诈：强力阻断，展示红盾拦截页
        await UrlInterstitialPage.open(
          context,
          checkResult: checkResult,
          title: title,
          fallbackContent: fallbackContent,
        );
        return;

      case UrlSecurityLevel.warning:
        // 普通第三方外链：展示风险过渡（微信同款黄盾中转页 或 警示弹窗）
        if (useInterstitialPage) {
          await UrlInterstitialPage.open(
            context,
            checkResult: checkResult,
            title: title,
            fallbackContent: fallbackContent,
          );
        } else {
          final action = await UrlRiskDialog.show(
            context,
            checkResult: checkResult,
          );
          if (action == UrlRiskDialogAction.openInternal && context.mounted) {
            await AppWebViewPage.open(
              context,
              url: trimmed,
              title: title,
              fallbackContent: fallbackContent,
            );
          }
        }
        return;
    }
  }
}

/// Provider for UrlSecurityService
final urlSecurityServiceProvider = Provider<UrlSecurityService>((ref) {
  final repo = ref.watch(urlSecurityRepositoryProvider);
  return UrlSecurityService(repository: repo);
});
