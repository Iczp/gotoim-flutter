import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/scan/scan_code_service.dart';

class ScanCodeDiagnosticsPage extends ConsumerStatefulWidget {
  const ScanCodeDiagnosticsPage({super.key});

  @override
  ConsumerState<ScanCodeDiagnosticsPage> createState() =>
      _ScanCodeDiagnosticsPageState();
}

class _ScanCodeDiagnosticsPageState
    extends ConsumerState<ScanCodeDiagnosticsPage> {
  ScanCodeResult? _result;
  String? _message;
  bool _opening = false;

  Future<void> _scan({required bool qrOnly}) async {
    setState(() {
      _opening = true;
      _message = null;
      _result = null;
    });
    try {
      final result = await ref.read(scanCodeServiceProvider).scanCode(
            Navigator.of(context),
            ScanCodeRequest(
              title: qrOnly ? '二维码测试' : '统一扫码测试',
              tip: qrOnly ? '仅识别二维码' : '支持二维码与常见条形码',
              formats: qrOnly
                  ? const <ScanCodeFormat>[ScanCodeFormat.qrCode]
                  : const <ScanCodeFormat>[],
            ),
          );
      if (mounted && result != null) {
        setState(() => _result = result);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = '扫码失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _opening = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(body: Center(child: Text('仅在 Debug 模式可用。')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('统一扫码测试')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('验证相机、扫描框动画、闪光灯、相册识别，以及 Web/桌面的上传图片识别。'),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _opening ? null : () => _scan(qrOnly: false),
            child: const Text('扫描所有支持的码'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _opening ? null : () => _scan(qrOnly: true),
            child: const Text('仅扫描二维码'),
          ),
          if (_opening)
            const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Center(child: CircularProgressIndicator())),
          if (_result != null) _ResultCard(result: _result!),
          if (_message != null)
            Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(_message!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});

  final ScanCodeResult result;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(top: 20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('识别结果', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              SelectableText('内容：${result.content}'),
              Text('格式：${result.format?.name ?? '未知'}'),
              Text('来源：${result.source.name}'),
            ],
          ),
        ),
      );
}
