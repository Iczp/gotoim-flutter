import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'scan_code_controller.dart';

/// The only reusable widget that directly hosts the camera plugin.
class ScanCodeCameraView extends StatelessWidget {
  const ScanCodeCameraView({super.key, required this.controller});

  final ScanCodeController controller;

  @override
  Widget build(BuildContext context) {
    final scanner = controller.scanner;
    if (scanner == null) {
      return const ColoredBox(
        color: Color(0xFF101010),
        child: Center(
          child: Text(
            '当前平台不支持相机扫码',
            style: TextStyle(color: Color(0xFFFFFFFF)),
          ),
        ),
      );
    }
    return MobileScanner(controller: scanner, onDetect: controller.onDetect);
  }
}
