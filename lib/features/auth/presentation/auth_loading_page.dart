import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AuthLoadingPage extends StatefulWidget {
  const AuthLoadingPage({super.key});

  @override
  State<AuthLoadingPage> createState() => _AuthLoadingPageState();
}

class _AuthLoadingPageState extends State<AuthLoadingPage> {
  bool _showEscapeOptions = false;
  Timer? _escapeTimer;

  @override
  void initState() {
    super.initState();
    _escapeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _showEscapeOptions = true);
      }
    });
  }

  @override
  void dispose() {
    _escapeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.forum_rounded,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Goto IM',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 32),
                const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(height: 16),
                Text(
                  '正在初始化应用...',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (_showEscapeOptions) ...[
                  const SizedBox(height: 32),
                  FilledButton.tonal(
                    onPressed: () => context.go('/login'),
                    child: const Text('前往登录页'),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => context.go('/diagnostics'),
                    icon: const Icon(Icons.build_circle_outlined, size: 18),
                    label: const Text('打开开发诊断中心'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
