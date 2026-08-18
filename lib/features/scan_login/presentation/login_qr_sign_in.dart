import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_environment.dart';
import '../../auth/application/auth_controller.dart';
import '../application/scan_login_hub.dart';
import 'qr_code_overlay.dart';

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
      throw const FormatException(
          'The scan-login service returned an empty QR code.');
    }
    setState(() {
      _qrText = challenge.scanText;
      _stateCode = state;
      _isExpired = false;
      _status = _QrLoginStatus.ready;
      _scanUserName = null;
    });
    final expiresAt = challenge.expiredTime;
    final expiresIn = expiresAt == null
        ? ref.read(appEnvironmentProvider).scanLoginFallbackExpires
        : expiresAt.difference(DateTime.now());
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
        return;
      }
      if (mounted) setState(() => _remainingSeconds = remaining);
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
      setState(() => _error = auth.errorMessage ?? 'Scan login failed.');
      _loggingIn = false;
    }
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
            ? '用户扫码成功，请在手机上确认登录。'
            : '用户 $user 扫码成功，请在手机上确认登录。';
      case _QrLoginStatus.rejected:
        return '用户拒绝了本次登录，请手动刷新二维码。';
      case _QrLoginStatus.cancelled:
        return '用户取消了本次登录，请手动刷新二维码。';
      case _QrLoginStatus.granted:
        return '用户已同意登录，正在登录…';
    }
  }

  String _errorMessage(Object error, {bool whileConnecting = false}) {
    final prefix = error is ScanLoginTokenException
        ? '获取扫码登录令牌失败'
        : whileConnecting
            ? '连接扫码登录服务失败'
            : '生成二维码失败';
    return '$prefix: ${error.toString().replaceFirst('Exception: ', '')}';
  }

  Future<void> _retry() => _connected ? _refresh() : _connectAndGenerate();

  @override
  Widget build(BuildContext context) {
    // Keep the auto-disposed hub alive for this page's whole lifetime.
    // A plain read from the async callback otherwise permits disposal between
    // widget rebuilds, producing repeated SignalR connect/disconnect cycles.
    ref.watch(scanLoginHubProvider);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('扫码登录',
            textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
        const SizedBox(height: 20),
        Center(
          child: SizedBox(
            width: 220,
            height: 220,
            child: !_connected
                ? Center(
                    child: _loading
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            // CircularProgressIndicator is not const on the
                            // Flutter version used by this project.
                            // ignore: prefer_const_literals_to_create_immutables
                            children: [
                              // ignore: prefer_const_constructors
                              CircularProgressIndicator(),
                              const SizedBox(height: 12),
                              const Text('正在连接扫码登录服务...'),
                            ],
                          )
                        : const Icon(Icons.wifi_off_outlined, size: 72),
                  )
                : _isExpired
                    ? const Icon(Icons.timer_off_outlined, size: 72)
                    : _loading && _qrText == null
                        ? const Center(child: CircularProgressIndicator())
                        : _qrText == null
                            ? const Icon(Icons.qr_code_2_outlined, size: 180)
                            : QrCodeOverlay(
                                data: _qrText!,
                                statusText: _statusText,
                              ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          !_connected
              ? (_loading ? '正在连接扫码登录服务...' : '连接失败，请重试。')
              : _isExpired
                  ? '二维码已过期，请手动刷新。'
                  : _stateCode == null
                      ? '正在生成二维码...'
                      : '请使用已登录的 Goto IM 扫描二维码。\n校验码：$_stateCode',
          textAlign: TextAlign.center,
        ),
        if (_connected &&
            !_isExpired &&
            _remainingSeconds != null &&
            (_status == _QrLoginStatus.ready ||
                _status == _QrLoginStatus.scanned)) ...[
          const SizedBox(height: 8),
          Text(
            '二维码有效期：${(_remainingSeconds! ~/ 60).toString().padLeft(2, '0')}:${(_remainingSeconds! % 60).toString().padLeft(2, '0')}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _loading || _loggingIn ? null : _retry,
          icon: const Icon(Icons.refresh),
          label: Text(_connected ? '刷新二维码' : '重新连接'),
        ),
      ],
    );
  }
}
