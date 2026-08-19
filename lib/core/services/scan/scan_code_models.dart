/// A barcode format accepted by [ScanCodeRequest].
///
/// An empty [ScanCodeRequest.formats] list means all formats supported by the
/// current platform, which is the appropriate default for most business flows.
enum ScanCodeFormat {
  qrCode,
  aztec,
  dataMatrix,
  pdf417,
  code128,
  code39,
  code93,
  codabar,
  ean13,
  ean8,
  itf,
  upcA,
  upcE,
}

enum ScanCodeSource { camera, album }

class ScanCodeRequest {
  const ScanCodeRequest({
    this.formats = const <ScanCodeFormat>[],
    this.title = '扫一扫',
    this.tip = '将二维码或条形码放入框内，即可自动扫描',
    this.allowAlbum = true,
    this.allowTorch = true,
  });

  final List<ScanCodeFormat> formats;
  final String title;
  final String tip;
  final bool allowAlbum;
  final bool allowTorch;
}

class ScanCodeResult {
  const ScanCodeResult({
    required this.content,
    required this.format,
    required this.source,
  });

  final String content;
  final ScanCodeFormat? format;
  final ScanCodeSource source;
}

class ScanCodeFailure implements Exception {
  const ScanCodeFailure(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}
