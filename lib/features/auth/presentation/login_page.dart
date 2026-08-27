import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/theme_mode_controller.dart';
import '../../../core/widgets/glass_container.dart';
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
    text: kDebugMode ? '1a2w3E*' : '',
  );
  bool _obscurePassword = true;
  bool _isQrLogin = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
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
                              Center(
                                child: Container(
                                  width: 68,
                                  height: 68,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        colorScheme.primary,
                                        colorScheme.tertiary,
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(18),
                                    boxShadow: [
                                      BoxShadow(
                                        color: colorScheme.primary.withValues(
                                          alpha: 0.35,
                                        ),
                                        blurRadius: 16,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.forum_rounded,
                                    size: 36,
                                    color: Colors.white,
                                  ),
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
    required this.onObscureChanged,
    required this.onSubmit,
  });

  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final bool isBusy;
  final String? errorMessage;
  final VoidCallback onObscureChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
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
        const SizedBox(height: 24),
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
