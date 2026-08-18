import 'scan_login_models.dart';

abstract class ScanLoginRepository {
  Future<ScanLoginRequest> inspect(String scanText);

  Future<void> grant(String scanText);

  Future<void> reject(String scanText, {String? reason});

  Future<void> cancel(String connectionId, {String? reason});
}
