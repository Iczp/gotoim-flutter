import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/scan/scan_code_service.dart';
import '../application/scan_login_controller.dart';

/// Business adapter for login scans. Camera and album implementation lives in
/// the shared ScanCodeService so every scan entry uses one experience.
class ScanLoginScanPage extends ConsumerStatefulWidget {
  const ScanLoginScanPage({super.key});

  @override
  ConsumerState<ScanLoginScanPage> createState() => _ScanLoginScanPageState();
}

class _ScanLoginScanPageState extends ConsumerState<ScanLoginScanPage> {
  bool _opening = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openScanner());
  }

  Future<void> _openScanner() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(scanCodeServiceProvider)
          .scanCode(
            Navigator.of(context),
            const ScanCodeRequest(
              title: '扫码登录',
              tip: '请扫描电脑端显示的登录二维码',
              formats: <ScanCodeFormat>[ScanCodeFormat.qrCode],
            ),
          );
      if (!mounted || result == null) return;
      final scanText = await ref
          .read(scanLoginRepositoryProvider)
          .resolveLoginScan(result.content, scanType: result.format?.name);
      if (!mounted) return;
      if (scanText == null) {
        setState(() => _error = '这不是有效的扫码登录二维码。');
        return;
      }
      context.go('/scan-login?scanText=${Uri.encodeQueryComponent(scanText)}');
    } catch (error) {
      if (mounted) setState(() => _error = '识别二维码失败：$error');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('扫码登录')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_opening)
              const CircularProgressIndicator()
            else
              const Icon(Icons.qr_code_scanner_outlined, size: 64),
            const SizedBox(height: 18),
            Text(_error ?? '正在打开扫码器…', textAlign: TextAlign.center),
            if (!_opening) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: _openScanner, child: const Text('重新扫码')),
            ],
          ],
        ),
      ),
    ),
  );
}
