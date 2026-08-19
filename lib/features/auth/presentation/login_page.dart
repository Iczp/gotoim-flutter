import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../scan_login/presentation/login_qr_sign_in.dart';
import '../application/auth_controller.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
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
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          Icons.forum_outlined,
                          size: 48,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Goto IM',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 28),
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
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                            onSubmit: _submit,
                          ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed:
                              auth.isBusy
                                  ? null
                                  : () =>
                                      setState(() => _isQrLogin = !_isQrLogin),
                          icon: Icon(
                            _isQrLogin
                                ? Icons.password_outlined
                                : Icons.qr_code_scanner_outlined,
                          ),
                          label: Text(_isQrLogin ? '使用密码登录' : '扫码登录'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
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
    return Column(
      children: [
        TextFormField(
          controller: usernameController,
          autofillHints: const [AutofillHints.username],
          decoration: const InputDecoration(
            labelText: '账号',
            border: OutlineInputBorder(),
          ),
          validator:
              (value) =>
                  value == null || value.trim().isEmpty
                      ? 'Enter your account.'
                      : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: passwordController,
          obscureText: obscurePassword,
          autofillHints: const [AutofillHints.password],
          decoration: InputDecoration(
            labelText: '密码',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: obscurePassword ? 'Show password' : 'Hide password',
              icon: Icon(
                obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              onPressed: onObscureChanged,
            ),
          ),
          onFieldSubmitted: (_) => onSubmit(),
          validator:
              (value) =>
                  value == null || value.isEmpty
                      ? 'Enter your password.'
                      : null,
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: 16),
          Text(errorMessage!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: isBusy ? null : onSubmit,
          child:
              isBusy
                  ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Text('登录'),
        ),
      ],
    );
  }
}
