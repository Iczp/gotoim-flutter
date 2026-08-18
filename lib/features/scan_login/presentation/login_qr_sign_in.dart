import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_environment.dart';
import '../../auth/application/auth_controller.dart';
import '../application/scan_login_hub.dart';
import 'qr_code_overlay.dart';
import 'verification_code_boxes.dart';

enum _QrLoginStatus { ready, scanned, rejected, cancelled, granted }

class LoginQrSignIn extends ConsumerStatefulWidget {
  const LoginQrSignIn({super.key});

  @override
  ConsumerState<LoginQrSignIn> createState() => _LoginQrSignInState();
}

class _LoginQrSignInState extends ConsumerState<LoginQrSignIn> {
  StreamSubscription<ScanLoginHubEvent>? _events;
  Timer? _expiryTimer;
  String? _qrText;
  String? _stateCode;
  String? _error;
  bool _loading = true;
  bool _connected = false;
  bool _isExpired = false;
  int? _remainingSeconds;
  _QrLoginStatus _status = _QrLoginStatus.ready;
  String? _scanUserName;
  bool _loggingIn = false;

  ScanLoginHub get _hub => ref.read(scanLoginHubProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _connectAndGenerate());
  }

  @override
  void dispose() {
    _events?.cancel();
    _expiryTimer?.cancel();
    super.dispose();
  }

  Future<void> _connectAndGenerate() async {
    setState(() {
      _loading = true;
      _connected = false;
      _error = null;
    });
    try {
      await _hub.connect();
      if (mounted) setState(() => _connected = true);
      _events ??= _hub.events.listen(_onHubEvent);
      await _generate();
    } catch (error) {
      if (mounted) {
        setState(() {
          _connected = false;
          _error = _errorMessage(error, whileConnecting: true);
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generate() async {
    _expiryTimer?.cancel();
    final state = (Random.secure().nextInt(9000) + 1000).toString();
    final challenge = await _hub.generate(state);
    if (!mounted) return;
    if (challenge.scanText.isEmpty) {
      throw const FormatException('扫码登录服务未返回二维码。');
    }
    setState(() {
      _qrText = challenge.scanText;
      _stateCode = state;
      _isExpired = false;
      _status = _QrLoginStatus.ready;
      _scanUserName = null;
    });
    final expiresIn = challenge.expiredTime == null
        ? ref.read(appEnvironmentProvider).scanLoginFallbackExpires
        : challenge.expiredTime!.difference(DateTime.now());
    _startCountdown(expiresIn);
  }

  void _startCountdown(Duration expiresIn) {
    _expiryTimer?.cancel();
    var remaining = expiresIn.isNegative ? 0 : expiresIn.inSeconds;
    setState(() => _remainingSeconds = remaining);
    if (remaining <= 0) {
      _markExpired();
      return;
    }
    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      remaining--;
      if (remaining <= 0) {
        _markExpired();
      } else if (mounted) {
        setState(() => _remainingSeconds = remaining);
      }
    });
  }

  void _markExpired() {
    _expiryTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _remainingSeconds = 0;
      _isExpired = true;
      _error = '二维码已过期，请手动刷新。';
    });
  }

  void _onHubEvent(ScanLoginHubEvent event) {
    switch (event.command) {
      case 'scanned':
        if (mounted) {
          setState(() {
            _status = _QrLoginStatus.scanned;
            _scanUserName = event.payload['scanUserName']?.toString() ??
                event.payload['userName']?.toString();
          });
        }
        break;
      case 'granted':
        final token = event.scanToken;
        if (token != null && token.isNotEmpty) {
          _expiryTimer?.cancel();
          if (mounted) setState(() => _status = _QrLoginStatus.granted);
          Future<void>.delayed(
            const Duration(milliseconds: 800),
            () => _completeLogin(token),
          );
        }
        break;
      case 'rejected':
        if (mounted) setState(() => _status = _QrLoginStatus.rejected);
        break;
      case 'cancelled':
        if (mounted) setState(() => _status = _QrLoginStatus.cancelled);
        break;
    }
  }

  Future<void> _completeLogin(String scanToken) async {
    if (_loggingIn) return;
    _loggingIn = true;
    await ref.read(authControllerProvider).loginWithScanToken(scanToken);
    if (!mounted) return;
    final auth = ref.read(authControllerProvider);
    if (auth.status == AuthStatus.authenticated) {
      context.go('/');
    } else {
      setState(() {
        _error = auth.errorMessage ?? '扫码登录失败，请重试。';
        _loggingIn = false;
      });
    }
  }

  Future<void> _requestRefresh() async {
    if (_loading || _loggingIn) return;
    if (_status == _QrLoginStatus.scanned) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('确认刷新二维码？'),
          content: const Text('手机端正在等待授权。刷新后，本次扫码登录将失效。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('继续等待'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('确认刷新'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await _refresh();
  }

  Future<void> _refresh() async {
    if (_loading || _loggingIn) return;
    try {
      setState(() {
        _loading = true;
        _error = null;
      });
      await _generate();
    } catch (error) {
      if (mounted) {
        setState(() {
          if (error is StateError) _connected = false;
          _error = _errorMessage(error);
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? get _statusText {
    switch (_status) {
      case _QrLoginStatus.ready:
        return null;
      case _QrLoginStatus.scanned:
        final user = _scanUserName;
        return user == null || user.isEmpty
            ? '扫码成功\n请在手机上确认登录'
            : '$user 扫码成功\n请在手机上确认登录';
      case _QrLoginStatus.rejected:
        return '用户拒绝了本次登录\n请手动刷新二维码';
      case _QrLoginStatus.cancelled:
        return '用户取消了本次登录\n请手动刷新二维码';
      case _QrLoginStatus.granted:
        return '用户已同意登录\n正在安全登录…';
    }
  }

  Color get _accentColor {
    if (_isExpired) return Colors.red;
    if ((_remainingSeconds ?? 999) <= 20) return Colors.deepOrange;
    switch (_status) {
      case _QrLoginStatus.scanned:
        return Colors.deepPurple;
      case _QrLoginStatus.granted:
        return Colors.green;
      case _QrLoginStatus.rejected:
      case _QrLoginStatus.cancelled:
        return Colors.orange;
      case _QrLoginStatus.ready:
        return Colors.indigo;
    }
  }

  String _errorMessage(Object error, {bool whileConnecting = false}) {
    final prefix = error is ScanLoginTokenException
        ? '获取扫码登录令牌失败'
        : whileConnecting
            ? '连接扫码登录服务失败'
            : '生成二维码失败';
    return '$prefix：${error.toString().replaceFirst('Exception: ', '')}';
  }

  String get _countdownText {
    final remaining = _remainingSeconds ?? 0;
    return '${(remaining ~/ 60).toString().padLeft(2, '0')}:${(remaining % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    // Keep the auto-disposed hub alive for this page's whole lifetime.
    ref.watch(scanLoginHubProvider);
    final theme = Theme.of(context);
    final hasQr = _connected && _qrText != null && !_isExpired;
    final isWarning = hasQr && (_remainingSeconds ?? 999) <= 20;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('扫码登录',
            textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
        const SizedBox(height: 6),
        Text('使用已登录的 Goto IM 扫描二维码',
            textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        const SizedBox(height: 20),
        Center(
          child: InkWell(
            onTap:
                _connected && !_loading && !_loggingIn ? _requestRefresh : null,
            borderRadius: BorderRadius.circular(24),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 258,
              height: 258,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _accentColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(24),
                border:
                    Border.all(color: _accentColor, width: isWarning ? 3 : 2),
                boxShadow: [
                  BoxShadow(
                    color: _accentColor.withOpacity(isWarning ? 0.35 : 0.16),
                    blurRadius: isWarning ? 22 : 12,
                    spreadRadius: isWarning ? 2 : 0,
                  ),
                ],
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: !_connected
                      ? _ConnectionState(loading: _loading)
                      : _isExpired
                          ? Icon(Icons.timer_off_outlined,
                              size: 76, color: _accentColor)
                          : _loading && _qrText == null
                              ? const CircularProgressIndicator()
                              : _qrText == null
                                  ? Icon(Icons.qr_code_2_outlined,
                                      size: 156, color: _accentColor)
                                  : QrCodeOverlay(
                                      data: _qrText!, statusText: _statusText),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (_stateCode != null && _connected) ...[
          Text('四位校验码',
              textAlign: TextAlign.center, style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          VerificationCodeBoxes(code: _stateCode, color: _accentColor),
        ],
        const SizedBox(height: 16),
        Text(
          !_connected
              ? (_loading ? '正在连接扫码登录服务…' : '连接失败，请重新连接。')
              : _isExpired
                  ? '二维码已过期，请点击下方按钮刷新。'
                  : _status == _QrLoginStatus.ready
                      ? '点击二维码可立即刷新'
                      : _statusText ?? '',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: _accentColor),
        ),
        if (_connected && !_isExpired && _remainingSeconds != null) ...[
          const SizedBox(height: 10),
          Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: _accentColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isWarning ? '即将过期  $_countdownText' : '二维码有效期  $_countdownText',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: _accentColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _loading || _loggingIn ? null : _requestRefresh,
          icon: const Icon(Icons.refresh),
          label: Text(_connected ? '刷新二维码' : '重新连接'),
        ),
      ],
    );
  }
}

class _ConnectionState extends StatelessWidget {
  const _ConnectionState({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) => loading
      ? Column(
          mainAxisSize: MainAxisSize.min,
          // The progress indicator is not const in this Flutter SDK.
          // ignore: prefer_const_literals_to_create_immutables
          children: [
            // ignore: prefer_const_constructors
            CircularProgressIndicator(),
            const SizedBox(height: 12),
            const Text('正在连接…'),
          ],
        )
      : const Icon(Icons.wifi_off_outlined, size: 72);
}
