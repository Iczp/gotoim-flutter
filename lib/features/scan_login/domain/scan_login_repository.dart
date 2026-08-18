import 'scan_login_models.dart';

abstract class ScanLoginRepository {
  Future<ScanLoginRequest> inspect(String scanText);

  Future<void> grant(String scanText);

  Future<void> reject(String scanText, {String? reason});

  Future<void> cancel(String connectionId, {String? reason});

  /// Resolves raw QR content through the existing backend scan handlers.
  /// Returns null when the QR code is not a login QR code.
  Future<String?> resolveLoginScan(String content, {String? scanType});
}
