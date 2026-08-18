import '../../../core/config/app_environment.dart';
import '../../../core/device/client_device_context.dart';
import 'scan_login_hub.dart';

ScanLoginHub createScanLoginHub({
  required AppEnvironment environment,
  required ClientDeviceContext deviceContext,
  required Future<String> Function() readAccessToken,
}) =>
    throw UnsupportedError('Scan-login is not supported by this runtime.');
