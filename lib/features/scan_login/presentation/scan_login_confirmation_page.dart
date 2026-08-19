import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_environment.dart';
import '../application/scan_login_controller.dart';
import '../domain/scan_login_models.dart';
import 'verification_code_boxes.dart';

/// The mobile authorization page shown after a login QR code is scanned.
/// Its countdown follows the `expiredTime` returned by the scan-login API.
class ScanLoginConfirmationPage extends ConsumerStatefulWidget {
  const ScanLoginConfirmationPage({super.key, required this.scanText});

  final String scanText;

  @override
  ConsumerState<ScanLoginConfirmationPage> createState() =>
      _ScanLoginConfirmationPageState();
}

class _ScanLoginConfirmationPageState
    extends ConsumerState<ScanLoginConfirmationPage> {
  Timer? _expiryTimer;
  DateTime? _expiresAt;
  int? _remainingSeconds;
  bool _expired = false;

  ScanLoginController get _controller =>
      ref.read(scanLoginControllerProvider(widget.scanText));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    _expiryTimer?.cancel();
    if (mounted) {
      setState(() {
        _expired = false;
        _remainingSeconds = null;
        _expiresAt = null;
      });
    }
    await _controller.load();
    if (!mounted) return;
    if (_controller.expired) {
      await _leaveAfterExpiry();
      return;
    }
    final request = _controller.request;
    if (request != null) _startCountdown(request);
  }

  void _startCountdown(ScanLoginRequest request) {
    // The server time is authoritative. The configured duration is only a
    // graceful fallback for older servers that do not return expiredTime.
    _expiresAt =
        request.expiredTime ??
        DateTime.now().add(
          ref.read(appEnvironmentProvider).scanLoginFallbackExpires,
        );
    _tickCountdown();
    if (!_expired) {
      _expiryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _tickCountdown();
      });
    }
  }

  void _tickCountdown() {
    final expiresAt = _expiresAt;
    if (expiresAt == null || !mounted) return;
    final difference = expiresAt.difference(DateTime.now());
    final seconds =
        difference.inMilliseconds <= 0
            ? 0
            : (difference.inMilliseconds + 999) ~/ 1000;
    if (seconds == 0) {
      _expiryTimer?.cancel();
      setState(() {
        _remainingSeconds = 0;
        _expired = true;
      });
      _leaveAfterExpiry();
      return;
    }
    setState(() => _remainingSeconds = seconds);
  }

  Future<void> _leaveAfterExpiry() async {
    await _controller.cancelIfNeeded();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('登录二维码已过期，请重新扫码。')));
    context.go('/');
  }

  Future<bool> _onWillPop() async {
    await _controller.cancelIfNeeded();
    if (mounted) context.go('/');
    return false;
  }

  Future<void> _submit({required bool approved}) async {
    if (_expired) return;
    final success =
        approved ? await _controller.grant() : await _controller.reject();
    if (!mounted) return;
    if (_controller.expired) {
      await _leaveAfterExpiry();
      return;
    }
    if (!success) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(approved ? '已同意本次登录。' : '已拒绝本次登录。')));
    context.go('/');
  }

  String get _countdownText {
    final seconds = _remainingSeconds;
    if (seconds == null) return '';
    final minutes = seconds ~/ 60;
    final remaining = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remaining.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(scanLoginControllerProvider(widget.scanText));
    final request = controller.request;
    final theme = Theme.of(context);
    final expiryWarning =
        (_remainingSeconds ?? 999) > 0 && (_remainingSeconds ?? 999) <= 20;
    final countdownColor =
        expiryWarning ? Colors.deepOrange : theme.colorScheme.primary;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_onWillPop());
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('确认登录')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child:
                  controller.loading
                      ? const Center(child: CircularProgressIndicator())
                      : controller.error != null && request == null
                      ? _ErrorState(
                        message:
                            controller.expired
                                ? '登录二维码已过期，请重新扫码。'
                                : '加载登录请求失败，请重试。',
                        actionLabel: controller.expired ? '返回重新扫码' : '重试',
                        onRetry: controller.expired ? _leaveAfterExpiry : _load,
                      )
                      : request == null
                      ? const SizedBox.shrink()
                      : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_remainingSeconds != null)
                            Center(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: countdownColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  expiryWarning
                                      ? '即将过期  $_countdownText'
                                      : '剩余时间  $_countdownText',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: countdownColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                          Icon(
                            Icons.devices_outlined,
                            size: 52,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            _expired ? '登录二维码已过期' : '是否允许此设备登录？',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 20),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _DeviceField(
                                    '应用',
                                    request.device.appName ?? '未提供',
                                  ),
                                  _DeviceField(
                                    '设备',
                                    request.device.deviceInfo ?? '未提供',
                                  ),
                                  _DeviceField(
                                    '客户端',
                                    request.device.clientId ?? '未提供',
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '授权账号：${request.scanUserName ?? '当前账号'}',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '四位校验码',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelLarge,
                          ),
                          const SizedBox(height: 8),
                          VerificationCodeBoxes(
                            code: request.state,
                            color: countdownColor,
                          ),
                          if (controller.error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              controller.authorizationAttempted
                                  ? '授权请求未确认，请返回后重新扫码。'
                                  : '操作失败：${controller.error}',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ],
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed:
                                      controller.submitting ||
                                              controller
                                                  .authorizationAttempted ||
                                              _expired
                                          ? null
                                          : () => _submit(approved: false),
                                  child: const Text('拒绝'),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: FilledButton(
                                  onPressed:
                                      controller.submitting ||
                                              controller
                                                  .authorizationAttempted ||
                                              !request.canAuthorize ||
                                              _expired
                                          ? null
                                          : () => _submit(approved: true),
                                  child:
                                      controller.submitting
                                          ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                          : const Text('同意登录'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeviceField extends StatelessWidget {
  const _DeviceField(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Text('$label：$value'),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.actionLabel,
    required this.onRetry,
  });

  final String message;
  final String actionLabel;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(message),
      const SizedBox(height: 12),
      FilledButton(onPressed: onRetry, child: Text(actionLabel)),
    ],
  );
}
