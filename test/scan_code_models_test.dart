import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/platform/platform_contract.dart';
import 'package:gotoim_flutter/core/services/scan/image_code_decoder.dart';
import 'package:gotoim_flutter/core/services/scan/scan_code_controller.dart';
import 'package:gotoim_flutter/core/services/scan/scan_code_models.dart';

void main() {
  test(
    'scan code request defaults to all formats and enables common actions',
    () {
      const request = ScanCodeRequest();

      expect(request.formats, isEmpty);
      expect(request.allowAlbum, isTrue);
      expect(request.allowTorch, isTrue);
    },
  );

  test('scan code result retains content, format and source', () {
    const result = ScanCodeResult(
      content: 'gotoim://scan-login?code=abc',
      format: ScanCodeFormat.qrCode,
      source: ScanCodeSource.album,
    );

    expect(result.content, contains('scan-login'));
    expect(result.format, ScanCodeFormat.qrCode);
    expect(result.source, ScanCodeSource.album);
  });

  test('scan-code formats use the backend handler values', () {
    expect(ScanCodeFormat.qrCode.apiValue, 'QR_CODE');
    expect(ScanCodeFormat.code128.apiValue, 'BAR_CODE');
  });

  test('image decode request defaults to QR code and album source', () {
    final request = DecodeImageRequest(bytes: Uint8List(0));

    expect(request.formats, <ScanCodeFormat>[ScanCodeFormat.qrCode]);
    expect(request.source, ScanCodeSource.album);
  });

  test('desktop and web keep the API but do not create a camera scanner', () {
    for (final kind in <PlatformKind>[PlatformKind.windows, PlatformKind.web]) {
      final controller = ScanCodeController(
        request: const ScanCodeRequest(),
        platform: _FakePlatformFacade(kind),
        onResult: (_) {},
      );
      addTearDown(controller.dispose);

      expect(controller.supportsCamera, isFalse, reason: '$kind');
      expect(controller.scanner, isNull, reason: '$kind');
    }
  });
}

class _FakePlatformFacade implements PlatformFacade {
  const _FakePlatformFacade(this.kind);

  @override
  final PlatformKind kind;

  @override
  bool get isWeb => kind == PlatformKind.web;

  @override
  bool get supportsMultipleWindows => false;

  @override
  bool get supportsNativeFilePaths => kind != PlatformKind.web;
}
