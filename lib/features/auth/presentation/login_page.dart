import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/compliance/agreement_viewer_page.dart';
import '../../../core/compliance/privacy_service.dart';
import '../../../core/theme/theme_mode_controller.dart';
import '../../../core/widgets/app_toast.dart';
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
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isQrLogin = false;
  bool _isRegister = false;
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
    _confirmPasswordController.dispose();
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
      final actionLabel = _isRegister ? '注册' : '登录';
      final agreed = await showDialog<bool>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: const Text('服务协议与隐私保护提醒'),
              content: Text(
                '请您在$actionLabel前阅读并同意《用户服务协议》与《隐私保护政策》。若同意，我们将为您${_isRegister ? '创建即时通讯账号并' : ''}建立会话协同服务。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('暂不同意'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text('同意并$actionLabel'),
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

    if (_isRegister) {
      try {
        await ref
            .read(authControllerProvider)
            .register(
              username: _usernameController.text.trim(),
              password: _passwordController.text,
            );
        if (mounted &&
            ref.read(authControllerProvider).status ==
                AuthStatus.authenticated) {
          showToast('注册成功，已自动登录', type: ToastType.success);
          context.go('/');
        }
      } catch (_) {
        // Error message is managed by AuthController.errorMessage
      }
    } else {
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
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: GlassContainer(
                        borderRadius: BorderRadius.circular(22),
                        blurSigma: 24,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 18,
                        ),
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
                                  size: 54,
                                  enableBreathing: true,
                                  heroTag: 'app_brand_logo',
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                _isRegister ? '加入 Goto IM' : 'Goto IM',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                  fontSize: 22,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isRegister ? '创建即时通讯协同账号' : '跨平台统一即时通讯客户端',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 16),
                              if (_isQrLogin)
                                const LoginQrSignIn()
                              else
                                _PasswordForm(
                                  isRegister: _isRegister,
                                  usernameController: _usernameController,
                                  passwordController: _passwordController,
                                  confirmPasswordController:
                                      _confirmPasswordController,
                                  obscurePassword: _obscurePassword,
                                  obscureConfirmPassword:
                                      _obscureConfirmPassword,
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
                                  onObscureConfirmChanged:
                                      () => setState(
                                        () =>
                                            _obscureConfirmPassword =
                                                !_obscureConfirmPassword,
                                      ),
                                  onSubmit: _submit,
                                ),
                              const SizedBox(height: 8),
                              if (!_isQrLogin && !_isRegister)
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    TextButton(
                                      onPressed:
                                          auth.isBusy
                                              ? null
                                              : () {
                                                setState(() {
                                                  _isRegister = true;
                                                  _formKey.currentState
                                                      ?.reset();
                                                });
                                              },
                                      child: const Text(
                                        '没有账号？立即注册',
                                        style: TextStyle(fontSize: 13),
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed:
                                          auth.isBusy
                                              ? null
                                              : () => setState(
                                                () => _isQrLogin = true,
                                              ),
                                      icon: const Icon(
                                        Icons.qr_code_scanner_rounded,
                                        size: 16,
                                      ),
                                      label: const Text(
                                        '扫码登录',
                                        style: TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  ],
                                )
                              else if (_isRegister)
                                Center(
                                  child: TextButton(
                                    onPressed:
                                        auth.isBusy
                                            ? null
                                            : () {
                                              setState(() {
                                                _isRegister = false;
                                                _formKey.currentState?.reset();
                                              });
                                            },
                                    child: const Text(
                                      '已有账号？返回登录',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                  ),
                                )
                              else
                                Center(
                                  child: TextButton.icon(
                                    onPressed:
                                        auth.isBusy
                                            ? null
                                            : () => setState(
                                              () => _isQrLogin = false,
                                            ),
                                    icon: const Icon(
                                      Icons.password_rounded,
                                      size: 16,
                                    ),
                                    label: const Text('使用账号密码登录'),
                                  ),
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
    required this.isRegister,
    required this.usernameController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.obscurePassword,
    required this.obscureConfirmPassword,
    required this.isBusy,
    required this.errorMessage,
    required this.agreeTerms,
    required this.onAgreeChanged,
    required this.onOpenUserAgreement,
    required this.onOpenPrivacyPolicy,
    required this.onObscureChanged,
    required this.onObscureConfirmChanged,
    required this.onSubmit,
  });

  final bool isRegister;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final bool obscurePassword;
  final bool obscureConfirmPassword;
  final bool isBusy;
  final String? errorMessage;
  final bool agreeTerms;
  final ValueChanged<bool?> onAgreeChanged;
  final VoidCallback onOpenUserAgreement;
  final VoidCallback onOpenPrivacyPolicy;
  final VoidCallback onObscureChanged;
  final VoidCallback onObscureConfirmChanged;
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
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            labelText: '账号',
            hintText: '请输入账号 / 用户名',
            prefixIcon: Icon(Icons.person_outline_rounded, size: 19),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) return '请输入账号';
            if (isRegister && value.trim().length < 3) return '账号长度至少3位';
            return null;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: passwordController,
          obscureText: obscurePassword,
          autofillHints: const [AutofillHints.password],
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 11,
            ),
            labelText: '密码',
            hintText: isRegister ? '请设置登录密码（至少6位）' : '请输入登录密码',
            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 19),
            suffixIcon: IconButton(
              tooltip: obscurePassword ? '显示密码' : '隐藏密码',
              icon: Icon(
                obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 19,
              ),
              onPressed: onObscureChanged,
            ),
          ),
          onFieldSubmitted: (_) => isRegister ? null : onSubmit(),
          validator: (value) {
            if (value == null || value.isEmpty) return '请输入密码';
            if (isRegister && value.length < 6) return '密码长度至少6位';
            return null;
          },
        ),
        if (isRegister) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: confirmPasswordController,
            obscureText: obscureConfirmPassword,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 11,
              ),
              labelText: '确认密码',
              hintText: '请再次输入密码',
              prefixIcon: const Icon(Icons.lock_reset_rounded, size: 19),
              suffixIcon: IconButton(
                tooltip: obscureConfirmPassword ? '显示密码' : '隐藏密码',
                icon: Icon(
                  obscureConfirmPassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 19,
                ),
                onPressed: onObscureConfirmChanged,
              ),
            ),
            onFieldSubmitted: (_) => onSubmit(),
            validator: (value) {
              if (value == null || value.isEmpty) return '请再次输入密码';
              if (value != passwordController.text) return '两次输入的密码不一致';
              return null;
            },
          ),
        ],
        if (errorMessage != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 16,
                  color: colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    errorMessage!,
                    style: TextStyle(color: colorScheme.error, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 20,
              height: 20,
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
                    fontSize: 11.5,
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
        const SizedBox(height: 14),
        FilledButton(
          onPressed: isBusy ? null : onSubmit,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
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
                  : Text(
                    isRegister ? '注 册' : '登 录',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2,
                    ),
                  ),
        ),
      ],
    );
  }
}
