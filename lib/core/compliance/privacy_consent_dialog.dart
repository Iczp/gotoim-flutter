import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'agreement_viewer_page.dart';
import 'privacy_service.dart';

/// Modal dialog strictly following App Store & regulatory privacy compliance standards.
class PrivacyConsentDialog extends StatelessWidget {
  const PrivacyConsentDialog({
    required this.privacyService,
    this.onAgreed,
    super.key,
  });

  final PrivacyService privacyService;
  final VoidCallback? onAgreed;

  static Future<bool> show(
    BuildContext context, {
    required PrivacyService privacyService,
    VoidCallback? onAgreed,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogContext) => PrivacyConsentDialog(
        privacyService: privacyService,
        onAgreed: onAgreed,
      ),
    );
    return result ?? false;
  }

  void _openAgreement(BuildContext context, String title, String content) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => AgreementViewerPage(title: title, content: content),
      ),
    );
  }

  Future<void> _handleDisagree(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (subContext) {
        final theme = Theme.of(subContext);
        final colorScheme = theme.colorScheme;
        return AlertDialog(
          title: const Text('温馨提示'),
          content: const Text(
            '若您不同意《用户服务协议》与《隐私保护政策》，我们将无法为您提供即时通讯、消息同步与协作服务。\n\n您是否确认退出应用？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(subContext).pop(false),
              child: const Text('返回并阅读'),
            ),
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.errorContainer,
                foregroundColor: colorScheme.onErrorContainer,
              ),
              onPressed: () => Navigator.of(subContext).pop(true),
              child: const Text('退出应用'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PopScope(
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        backgroundColor: theme.colorScheme.surface,
        elevation: 8,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title & Badge
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.shield_outlined,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '用户协议与隐私保护提示',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Scrollable Legal Summary with clickable links
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: SingleChildScrollView(
                    child: RichText(
                      text: TextSpan(
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.6,
                          fontSize: 13.5,
                          color: colorScheme.onSurface.withValues(alpha: 0.85),
                        ),
                        children: [
                          const TextSpan(
                            text:
                                '感谢您使用 GotoIM！在您开启畅快沟通前，请您务必认真阅读并充分理解 ',
                          ),
                          TextSpan(
                            text: '《${PrivacyService.userAgreementTitle}》',
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.underline,
                            ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () => _openAgreement(
                                context,
                                PrivacyService.userAgreementTitle,
                                PrivacyService.userAgreementContent,
                              ),
                          ),
                          const TextSpan(text: ' 与 '),
                          TextSpan(
                            text: '《${PrivacyService.privacyPolicyTitle}》',
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.underline,
                            ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () => _openAgreement(
                                context,
                                PrivacyService.privacyPolicyTitle,
                                PrivacyService.privacyPolicyContent,
                              ),
                          ),
                          const TextSpan(
                            text:
                                '。\n\n我们承诺严格遵守法律法规保护您的个人信息安全：\n'
                                '1. 我们会基于提供消息收发、群聊协作、图片/语音/视频发送及离线消息推送等核心功能，遵循“合法、正当、必要”原则申请设备存储、相机、麦克风等系统权限。\n'
                                '2. 未经您的明示授权，我们绝不会主动向第三方提供、出售您的个人隐私信息。\n'
                                '3. 您可在设置中随时查阅、更正个人资料或注销账号。\n\n'
                                '点击“同意并继续”即表示您已阅读并完全同意上述协议与条款。',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => _handleDisagree(context),
                      child: const Text('不同意并退出'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () async {
                        await privacyService.saveAgreement();
                        if (context.mounted) {
                          Navigator.of(context).pop(true);
                        }
                        onAgreed?.call();
                      },
                      child: const Text('同意并继续'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
