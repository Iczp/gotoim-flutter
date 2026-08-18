import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../auth/application/auth_controller.dart';
import '../application/scan_login_hub.dart';

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
      _error = null;
    });
    try {
      await _hub.connect();
      _events ??= _hub.events.listen(_onHubEvent);
      await _generate();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
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
    });
    final expiresAt = challenge.expiredTime;
    if (expiresAt != null) {
      final delay = expiresAt.difference(DateTime.now());
      _expiryTimer = Timer(delay.isNegative ? Duration.zero : delay, _refresh);
    }
  }

  void _onHubEvent(ScanLoginHubEvent event) {
    switch (event.command) {
      case 'granted':
        final token = event.scanToken;
        if (token != null && token.isNotEmpty) _completeLogin(token);
        break;
      case 'cancelled':
      case 'rejected':
        _refresh();
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
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Scan to sign in',
            textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
        const SizedBox(height: 20),
        Center(
          child: SizedBox(
            width: 220,
            height: 220,
            child: _loading && _qrText == null
                ? const Center(child: CircularProgressIndicator())
                : _qrText == null
                    ? const Icon(Icons.qr_code_2_outlined, size: 180)
                    : QrImage(data: _qrText!, size: 220),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _stateCode == null
              ? 'Preparing secure QR code...'
              : 'Open Goto IM on your phone and scan this code.\nVerification code: $_stateCode',
          textAlign: TextAlign.center,
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _loading || _loggingIn ? null : _refresh,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh QR code'),
        ),
      ],
    );
  }
}
