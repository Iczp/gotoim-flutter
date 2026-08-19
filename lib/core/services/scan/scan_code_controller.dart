import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../platform/platform_contract.dart';
import 'image_code_decoder.dart';
import 'scan_code_models.dart';

class ScanCodeController extends ChangeNotifier {
  ScanCodeController({
    required this.request,
    required PlatformFacade platform,
    required this.onResult,
    ImagePicker? imagePicker,
    ImageCodeService? imageCodeService,
  })  : _imagePicker = imagePicker ?? ImagePicker(),
        _imageCodeService = imageCodeService ?? const ZxingImageCodeService(),
        supportsCamera = _supportsCamera(platform),
        _scanner = _supportsCamera(platform)
            ? MobileScannerController(
                detectionSpeed: DetectionSpeed.noDuplicates,
                formats: _toMobileFormats(request.formats),
              )
            : null {
    _scanner?.addListener(_syncTorch);
  }

  final ScanCodeRequest request;
  final ValueChanged<ScanCodeResult> onResult;
  final ImagePicker _imagePicker;
  final ImageCodeService _imageCodeService;
  final bool supportsCamera;
  final MobileScannerController? _scanner;

  bool _completed = false;
  bool _busy = false;
  bool _torchEnabled = false;
  String? _error;

  MobileScannerController? get scanner => _scanner;
  bool get busy => _busy;
  bool get torchEnabled => _torchEnabled;
  String? get error => _error;

  static bool _supportsCamera(PlatformFacade platform) {
    return platform.kind == PlatformKind.android ||
        platform.kind == PlatformKind.ios;
  }

  static List<BarcodeFormat> _toMobileFormats(List<ScanCodeFormat> formats) {
    const mapping = <ScanCodeFormat, BarcodeFormat>{
      ScanCodeFormat.qrCode: BarcodeFormat.qrCode,
      ScanCodeFormat.aztec: BarcodeFormat.aztec,
      ScanCodeFormat.dataMatrix: BarcodeFormat.dataMatrix,
      ScanCodeFormat.pdf417: BarcodeFormat.pdf417,
      ScanCodeFormat.code128: BarcodeFormat.code128,
      ScanCodeFormat.code39: BarcodeFormat.code39,
      ScanCodeFormat.code93: BarcodeFormat.code93,
      ScanCodeFormat.codabar: BarcodeFormat.codabar,
      ScanCodeFormat.ean13: BarcodeFormat.ean13,
      ScanCodeFormat.ean8: BarcodeFormat.ean8,
      ScanCodeFormat.itf: BarcodeFormat.itf14,
      ScanCodeFormat.upcA: BarcodeFormat.upcA,
      ScanCodeFormat.upcE: BarcodeFormat.upcE,
    };
    return formats
        .map((format) => mapping[format])
        .whereType<BarcodeFormat>()
        .toList();
  }

  void onDetect(BarcodeCapture capture) =>
      _completeCapture(capture, ScanCodeSource.camera);

  void _completeCapture(
    BarcodeCapture capture,
    ScanCodeSource source, {
    bool allowWhileBusy = false,
  }) {
    if (_completed || (_busy && !allowWhileBusy)) return;
    Barcode? barcode;
    for (final item in capture.barcodes) {
      if (item.rawValue != null && item.rawValue!.trim().isNotEmpty) {
        barcode = item;
        break;
      }
    }
    final detectedBarcode = barcode;
    if (detectedBarcode == null) return;
    final content = detectedBarcode.rawValue?.trim();
    if (content == null || content.isEmpty) return;
    _completed = true;
    onResult(
      ScanCodeResult(
        content: content,
        format: _fromMobileFormat(detectedBarcode.format),
        source: source,
      ),
    );
  }

  Future<void> toggleTorch() async {
    if (_scanner == null) {
      _setError('当前平台不支持闪光灯。');
      return;
    }
    try {
      await _scanner?.toggleTorch();
      _syncTorch();
    } catch (error) {
      _setError('无法切换闪光灯。');
    }
  }

  Future<void> scanFromAlbum() async {
    if (_busy || _completed) return;
    try {
      _setBusy(true);
      if (_scanner == null) {
        await _uploadAndDecode();
      } else {
        final image = await _imagePicker.pickImage(source: ImageSource.gallery);
        if (image == null) return;
        // Delegate image recognition to the native scanner on mobile. It uses
        // the same format configuration as the live camera instead of
        // silently reducing an album scan to QR only.
        final capture = await _scanner?.analyzeImage(image.path);
        if (capture != null) {
          _completeCapture(capture, ScanCodeSource.album, allowWhileBusy: true);
        }
        if (!_completed) {
          _setError('未在图片中识别到可用的二维码或条形码，请上传清晰的图片。');
        }
      }
    } catch (error) {
      _setError('相册识别失败，请更换清晰的图片。');
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _uploadAndDecode() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.image,
      dialogTitle: '上传二维码图片',
    );
    if (picked.isEmpty) return;
    final bytes = await picked.single.readAsBytes();
    await _decodeImageBytes(bytes);
  }

  Future<void> _decodeImageBytes(Uint8List bytes) async {
    final result = await _imageCodeService.decodeImage(
      DecodeImageRequest(
        bytes: bytes,
        formats: request.formats,
        source: ScanCodeSource.album,
      ),
    );
    if (result == null) {
      _setError('未在图片中识别到二维码，请上传清晰的二维码图片。');
      return;
    }
    _completed = true;
    onResult(result);
  }

  void _syncTorch() {
    _torchEnabled = _scanner?.value.torchState == TorchState.on;
    notifyListeners();
  }

  void _setBusy(bool value) {
    _busy = value;
    notifyListeners();
  }

  void _setError(String value) {
    _error = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _scanner?.removeListener(_syncTorch);
    _scanner?.dispose();
    super.dispose();
  }
}

ScanCodeFormat? _fromMobileFormat(BarcodeFormat format) {
  const mapping = <BarcodeFormat, ScanCodeFormat>{
    BarcodeFormat.qrCode: ScanCodeFormat.qrCode,
    BarcodeFormat.aztec: ScanCodeFormat.aztec,
    BarcodeFormat.dataMatrix: ScanCodeFormat.dataMatrix,
    BarcodeFormat.pdf417: ScanCodeFormat.pdf417,
    BarcodeFormat.code128: ScanCodeFormat.code128,
    BarcodeFormat.code39: ScanCodeFormat.code39,
    BarcodeFormat.code93: ScanCodeFormat.code93,
    BarcodeFormat.codabar: ScanCodeFormat.codabar,
    BarcodeFormat.ean13: ScanCodeFormat.ean13,
    BarcodeFormat.ean8: ScanCodeFormat.ean8,
    BarcodeFormat.itf14: ScanCodeFormat.itf,
    BarcodeFormat.upcA: ScanCodeFormat.upcA,
    BarcodeFormat.upcE: ScanCodeFormat.upcE,
  };
  return mapping[format];
}
