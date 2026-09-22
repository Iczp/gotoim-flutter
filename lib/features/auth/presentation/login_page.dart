import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/compliance/agreement_viewer_page.dart';
import '../../../core/compliance/privacy_service.dart';
import '../../../core/theme/theme_mode_controller.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/widgets/gotoim_logo.dart';
import '../../scan_login/presentation/login_qr_sign_in.dart';
import '../application/auth_controller.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController(
    text: kDebugMode ? 'admin' : '',
  );
  final _passwordController = TextEditingController(
    text: kDebugMode ? '1q2w3E*' : '',
  );
  bool _obscurePassword = true;
  bool _isQrLogin = false;
  bool _agreeTerms = false;

  @override
  void initState() {
    super.initState();
    _agreeTerms = ref.read(privacyServiceProvider).hasAgreed;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _openUserAgreement() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => const AgreementViewerPage(
              title: PrivacyService.userAgreementTitle,
              content: PrivacyService.userAgreementContent,
              url: PrivacyService.userAgreementUrl,
            ),
      ),
    );
  }

  void _openPrivacyPolicy() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => const AgreementViewerPage(
              title: PrivacyService.privacyPolicyTitle,
              content: PrivacyService.privacyPolicyContent,
              url: PrivacyService.privacyPolicyUrl,
            ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (!_agreeTerms) {
      final agreed = await showDialog<bool>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: const Text('服务协议与隐私保护提醒'),
              content: const Text(
                '请您在登录前阅读并同意《用户服务协议》与《隐私保护政策》。若同意，我们将为您建立账号会话并开启即时通讯协同服务。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('暂不同意'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('同意并登录'),
                ),
              ],
            ),
      );

      if (agreed == true) {
        setState(() {
          _agreeTerms = true;
        });
        await ref.read(privacyServiceProvider).saveAgreement();
      } else {
        return;
      }
    } else {
      await ref.read(privacyServiceProvider).saveAgreement();
    }

    await ref
        .read(authControllerProvider)
        .login(
          username: _usernameController.text.trim(),
          password: _passwordController.text,
        );
    if (mounted &&
        ref.read(authControllerProvider).status == AuthStatus.authenticated) {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final themeMode = ref.watch(themeModeProvider);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          // Background ambient glowing gradients for modern frosted glass refraction
          Positioned(
            top: -80,
            left: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    colorScheme.primary.withValues(alpha: isDark ? 0.35 : 0.25),
                    colorScheme.primary.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -60,
            right: -60,
            child: Container(
              width: 360,
              height: 360,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    colorScheme.tertiary.withValues(
                      alpha: isDark ? 0.30 : 0.20,
                    ),
                    colorScheme.tertiary.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Stack(
              children: [
                Positioned(
                  top: 12,
                  right: 16,
                  child: IconButton(
                    tooltip: '切换浅色/深色主题',
                    icon: Icon(
                      themeMode == ThemeMode.dark
                          ? Icons.dark_mode_rounded
                          : themeMode == ThemeMode.light
                          ? Icons.light_mode_rounded
                          : Icons.brightness_auto_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    onPressed:
                        () =>
                            ref
                                .read(themeModeControllerProvider.notifier)
                                .toggleTheme(),
                  ),
                ),
                Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 32,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: GlassContainer(
                        borderRadius: BorderRadius.circular(24),
                        blurSigma: 24,
                        padding: const EdgeInsets.all(32),
                        boxShadow: [
                          BoxShadow(
                            color:
                                isDark
                                    ? Colors.black.withValues(alpha: 0.4)
                                    : colorScheme.primary.withValues(
                                      alpha: 0.08,
                                    ),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Center(
                                child: GotoImLogo(
                                  size: 78,
                                  enableBreathing: true,
                                  heroTag: 'app_brand_logo',
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'Goto IM',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '跨平台统一即时通讯客户端',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 32),
                              if (_isQrLogin)
                                const LoginQrSignIn()
                              else
                                _PasswordForm(
                                  usernameController: _usernameController,
                                  passwordController: _passwordController,
                                  obscurePassword: _obscurePassword,
                                  isBusy: auth.isBusy,
                                  errorMessage: auth.errorMessage,
                                  agreeTerms: _agreeTerms,
                                  onAgreeChanged: (val) {
                                    setState(() {
                                      _agreeTerms = val ?? false;
                                    });
                                  },
                                  onOpenUserAgreement: _openUserAgreement,
                                  onOpenPrivacyPolicy: _openPrivacyPolicy,
                                  onObscureChanged:
                                      () => setState(
                                        () =>
                                            _obscurePassword =
                                                !_obscurePassword,
                                      ),
                                  onSubmit: _submit,
                                ),
                              const SizedBox(height: 12),
                              TextButton.icon(
                                onPressed:
                                    auth.isBusy
                                        ? null
                                        : () => setState(
                                          () => _isQrLogin = !_isQrLogin,
                                        ),
                                icon: Icon(
                                  _isQrLogin
                                      ? Icons.password_rounded
                                      : Icons.qr_code_scanner_rounded,
                                  size: 18,
                                ),
                                label: Text(_isQrLogin ? '使用账号密码登录' : '扫码快速登录'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PasswordForm extends StatelessWidget {
  const _PasswordForm({
    required this.usernameController,
    required this.passwordController,
    required this.obscurePassword,
    required this.isBusy,
    required this.errorMessage,
    required this.agreeTerms,
    required this.onAgreeChanged,
    required this.onOpenUserAgreement,
    required this.onOpenPrivacyPolicy,
    required this.onObscureChanged,
    required this.onSubmit,
  });

  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final bool isBusy;
  final String? errorMessage;
  final bool agreeTerms;
  final ValueChanged<bool?> onAgreeChanged;
  final VoidCallback onOpenUserAgreement;
  final VoidCallback onOpenPrivacyPolicy;
  final VoidCallback onObscureChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: usernameController,
          autofillHints: const [AutofillHints.username],
          decoration: const InputDecoration(
            labelText: '账号',
            hintText: '请输入账号 / 用户名',
            prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
          ),
          validator:
              (value) => value == null || value.trim().isEmpty ? '请输入账号' : null,
        ),
        const SizedBox(height: 18),
        TextFormField(
          controller: passwordController,
          obscureText: obscurePassword,
          autofillHints: const [AutofillHints.password],
          decoration: InputDecoration(
            labelText: '密码',
            hintText: '请输入登录密码',
            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
            suffixIcon: IconButton(
              tooltip: obscurePassword ? '显示密码' : '隐藏密码',
              icon: Icon(
                obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 20,
              ),
              onPressed: onObscureChanged,
            ),
          ),
          onFieldSubmitted: (_) => onSubmit(),
          validator: (value) => value == null || value.isEmpty ? '请输入密码' : null,
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 18,
                  color: colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    errorMessage!,
                    style: TextStyle(color: colorScheme.error, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: agreeTerms,
                onChanged: onAgreeChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: '我已阅读并同意',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                  children: [
                    TextSpan(
                      text: '《用户服务协议》',
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                      recognizer:
                          TapGestureRecognizer()..onTap = onOpenUserAgreement,
                    ),
                    const TextSpan(text: '与'),
                    TextSpan(
                      text: '《隐私保护政策》',
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                      recognizer:
                          TapGestureRecognizer()..onTap = onOpenPrivacyPolicy,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: isBusy ? null : onSubmit,
          child:
              isBusy
                  ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                  : const Text('登 录', style: TextStyle(fontSize: 16)),
        ),
      ],
    );
  }
}
