import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/clipboard_service.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_repository.dart';
import '../application/connection_test_controller.dart';

class AuthDiagnosticsPage extends ConsumerStatefulWidget {
  const AuthDiagnosticsPage({super.key});

  @override
  ConsumerState<AuthDiagnosticsPage> createState() =>
      _AuthDiagnosticsPageState();
}

class _AuthDiagnosticsPageState extends ConsumerState<AuthDiagnosticsPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _accessToken;
  String? _refreshToken;

  @override
  void initState() {
    super.initState();
    _reloadTokens();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _reloadTokens() async {
    final controller = ref.read(connectionTestControllerProvider);
    final accessToken = await controller.readAccessToken();
    final refreshToken = await controller.readRefreshToken();
    if (mounted) {
      setState(() {
        _accessToken = accessToken;
        _refreshToken = refreshToken;
      });
    }
  }

  Future<void> _login() async {
    await ref
        .read(authControllerProvider)
        .login(
          username: _usernameController.text.trim(),
          password: _passwordController.text,
        );
    await _reloadTokens();
  }

  Future<void> _refresh() async {
    await ref.read(connectionTestControllerProvider).refreshToken();
    await _reloadTokens();
  }

  Future<void> _copy(String value) async {
    await ref.read(clipboardServiceProvider).copy(value);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已复制。')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(body: Center(child: Text('开发诊断仅在 Debug 模式可用。')));
    }
    final controller = ref.watch(connectionTestControllerProvider);
    final auth = ref.watch(authControllerProvider);
    final environment = controller.environment;
    final device = controller.deviceContext;
    return Scaffold(
      appBar: AppBar(title: const Text('认证与敏感凭据')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '仅限本地 Debug 联调。此页会显示密码输入与 Token，请勿录屏、截图或提交到版本库。',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 16),
          Text('登录参数', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _usernameController,
            decoration: const InputDecoration(
              labelText: '用户名',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _passwordController,
            obscureText: false,
            decoration: const InputDecoration(
              labelText: '密码（明文调试）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: auth.isBusy ? null : _login,
            child: const Text('登录并保存 Token'),
          ),
          if (auth.errorMessage != null) Text(auth.errorMessage!),
          const SizedBox(height: 20),
          Text('当前凭据', style: Theme.of(context).textTheme.titleMedium),
          _DebugValue(
            label: 'access token',
            value: _accessToken ?? '',
            onCopy: _copy,
          ),
          _DebugValue(
            label: 'refresh token',
            value: _refreshToken ?? '',
            onCopy: _copy,
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: _refresh,
                child: const Text('刷新 Token'),
              ),
              OutlinedButton(
                onPressed:
                    () => controller.introspectToken(
                      RevocationTokenType.accessToken,
                    ),
                child: const Text('检查 access token'),
              ),
              OutlinedButton(
                onPressed:
                    () => controller.introspectToken(
                      RevocationTokenType.refreshToken,
                    ),
                child: const Text('检查 refresh token'),
              ),
              OutlinedButton(
                onPressed:
                    () =>
                        controller.revokeToken(RevocationTokenType.accessToken),
                child: const Text('撤销 access token'),
              ),
              OutlinedButton(
                onPressed:
                    () => controller.revokeToken(
                      RevocationTokenType.refreshToken,
                    ),
                child: const Text('撤销 refresh token'),
              ),
              FilledButton.tonal(
                onPressed: () => ref.read(authControllerProvider).logout(),
                child: const Text('退出登录（撤销并清除）'),
              ),
            ],
          ),
          if (controller.authOperationError != null) ...[
            const SizedBox(height: 8),
            SelectableText(
              controller.authOperationError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (controller.authOperationResult != null) ...[
            const SizedBox(height: 8),
            SelectableText(controller.authOperationResult!),
          ],
          const SizedBox(height: 20),
          Text('当前配置与设备上下文', style: Theme.of(context).textTheme.titleMedium),
          _DebugValue(
            label: 'AUTH_BASE_URL',
            value: environment.authBaseUrl,
            onCopy: _copy,
          ),
          _DebugValue(
            label: 'AUTH_CLIENT_ID',
            value: environment.authClientId,
            onCopy: _copy,
          ),
          _DebugValue(
            label: 'AUTH_CLIENT_SECRET',
            value: environment.authClientSecret,
            onCopy: _copy,
          ),
          _DebugValue(label: 'deviceId', value: device.deviceId, onCopy: _copy),
          _DebugValue(
            label: 'deviceType',
            value: device.deviceType,
            onCopy: _copy,
          ),
        ],
      ),
    );
  }
}

class _DebugValue extends StatelessWidget {
  const _DebugValue({
    required this.label,
    required this.value,
    required this.onCopy,
  });

  final String label;
  final String value;
  final Future<void> Function(String value) onCopy;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: TextField(
      controller: TextEditingController(text: value),
      readOnly: true,
      minLines: 1,
      maxLines: 5,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: '复制',
          icon: const Icon(Icons.copy_outlined),
          onPressed: value.isEmpty ? null : () => onCopy(value),
        ),
      ),
    ),
  );
}
