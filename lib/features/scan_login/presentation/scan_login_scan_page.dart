import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/platform/platform_facade.dart';
import '../../../core/services/clipboard_service.dart';
import '../application/scan_login_controller.dart';

class ScanLoginScanPage extends ConsumerStatefulWidget {
  const ScanLoginScanPage({super.key});

  @override
  ConsumerState<ScanLoginScanPage> createState() => _ScanLoginScanPageState();
}

class _ScanLoginScanPageState extends ConsumerState<ScanLoginScanPage> {
  final _textController = TextEditingController();
  MobileScannerController? _cameraController;
  bool _resolving = false;
  String? _error;

  bool get _supportsCamera {
    final platform = ref.read(platformFacadeProvider);
    return platform.isWeb ||
        platform.kind == PlatformKind.android ||
        platform.kind == PlatformKind.ios ||
        platform.kind == PlatformKind.macos;
  }

  @override
  void initState() {
    super.initState();
    if (_supportsCamera) {
      _cameraController = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
      );
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    final value = capture.barcodes.map((item) => item.rawValue).firstWhere(
        (item) => item != null && item.isNotEmpty,
        orElse: () => null);
    if (value == null) return;
    await _resolve(value, scanType: 'QR_CODE');
  }

  Future<void> _paste() async {
    final text = await ref.read(clipboardServiceProvider).read();
    if (!mounted || text == null || text.trim().isEmpty) return;
    _textController.text = text.trim();
  }

  Future<void> _resolve(String content, {String? scanType}) async {
    if (_resolving || content.trim().isEmpty) return;
    setState(() {
      _resolving = true;
      _error = null;
    });
    try {
      final scanText = await ref
          .read(scanLoginRepositoryProvider)
          .resolveLoginScan(content.trim(), scanType: scanType);
      if (!mounted) return;
      if (scanText == null) {
        setState(() => _error = '这不是有效的扫码登录二维码。');
        return;
      }
      // Replace the camera page so it is disposed while the user authorizes
      // the request, matching the original UniApp navigation flow.
      context.go('/scan-login?scanText=${Uri.encodeQueryComponent(scanText)}');
    } catch (error) {
      if (mounted) setState(() => _error = '识别二维码失败：$error');
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('扫码登录')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              if (_supportsCamera)
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: MobileScanner(
                      controller: _cameraController,
                      onDetect: _onDetect,
                    ),
                  ),
                )
              else
                const Expanded(
                  child: Center(
                    child: Text('当前平台不支持相机扫码，请粘贴二维码内容。'),
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                _supportsCamera ? '请扫描登录二维码' : '粘贴登录二维码内容',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _textController,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: '二维码内容',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: '粘贴',
                    icon: const Icon(Icons.content_paste_outlined),
                    onPressed: _paste,
                  ),
                ),
                onSubmitted: (value) => _resolve(value),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed:
                    _resolving ? null : () => _resolve(_textController.text),
                child: _resolving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('识别并继续'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
