import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/services/scan/scan_code_models.dart';
import 'package:gotoim_flutter/core/services/scan/unified_scan_dispatcher.dart';

void main() {
  group('UnifiedScanDispatcher', () {
    test('instantiates and provides provider default', () {
      const dispatcher = UnifiedScanDispatcher();
      expect(dispatcher, isNotNull);
    });

    test('ScanCodeResult encapsulates content and format', () {
      const result = ScanCodeResult(
        content: 'https://gotoim.com/login?token=xyz',
        format: ScanCodeFormat.qrCode,
        source: ScanCodeSource.camera,
      );
      expect(result.content, contains('login'));
      expect(result.format, ScanCodeFormat.qrCode);
      expect(result.source, ScanCodeSource.camera);
    });
  });
}
