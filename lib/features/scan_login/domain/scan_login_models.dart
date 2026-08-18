class LoginDevice {
  const LoginDevice({
    required this.appName,
    required this.deviceInfo,
    required this.clientId,
  });

  final String? appName;
  final String? deviceInfo;
  final String? clientId;

  factory LoginDevice.fromJson(Map<String, dynamic> json) {
    return LoginDevice(
      appName: json['appName']?.toString(),
      deviceInfo: json['deviceInfo']?.toString(),
      clientId: json['clientId']?.toString(),
    );
  }
}

/// Data returned after the mobile client scans a login QR code.
///
/// This response deliberately contains the target device details shown to the
/// user before an authorization can be granted.
class ScanLoginRequest {
  const ScanLoginRequest({
    required this.connectionId,
    required this.scanUserId,
    required this.scanUserName,
    required this.device,
  });

  final String connectionId;
  final String? scanUserId;
  final String? scanUserName;
  final LoginDevice device;

  bool get canAuthorize => scanUserId != null && scanUserId!.isNotEmpty;

  factory ScanLoginRequest.fromJson(Map<String, dynamic> json) {
    final pool = json['connectionPool'];
    return ScanLoginRequest(
      connectionId: json['connectionId']?.toString() ?? '',
      scanUserId: json['scanUserId']?.toString(),
      scanUserName: json['scanUserName']?.toString(),
      device: LoginDevice.fromJson(
        pool is Map<String, dynamic>
            ? pool
            : pool is Map
                ? Map<String, dynamic>.from(pool)
                : const <String, dynamic>{},
      ),
    );
  }
}
