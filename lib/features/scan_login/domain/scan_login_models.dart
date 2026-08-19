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

/// Matches a scan-login QR code against the configured URI template.
///
/// For example, `gotoim://scan-login?code={code}` accepts a non-empty `code`
/// value while keeping all fixed text exact. Placeholders are supported in any
/// URI component, including a path segment and query value.
class ScanLoginTemplate {
  const ScanLoginTemplate(this.value);

  final String value;

  bool matches(String scanText) {
    final template = value.trim();
    final scanned = scanText.trim();
    if (template.isEmpty || scanned.isEmpty) return false;

    final placeholders = RegExp(r'\{[^{}]+\}').allMatches(template).toList();
    final pattern = StringBuffer('^');
    var cursor = 0;
    for (final placeholder in placeholders) {
      pattern.write(
        RegExp.escape(template.substring(cursor, placeholder.start)),
      );
      // Keep placeholder values in one URI component, matching the existing
      // mobile client TemplateBuilder behaviour.
      pattern.write(r'([^/?&#]+)');
      cursor = placeholder.end;
    }
    pattern.write(RegExp.escape(template.substring(cursor)));
    pattern.write(r'$');

    final match = RegExp(pattern.toString()).firstMatch(scanned);
    if (match == null) return false;
    return List<int>.generate(
      placeholders.length,
      (index) => index + 1,
    ).every((index) => (match.group(index) ?? '').isNotEmpty);
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
    this.state,
    this.expiredTime,
  });

  final String connectionId;
  final String? scanUserId;
  final String? scanUserName;
  final LoginDevice device;
  final String? state;
  final DateTime? expiredTime;

  bool get canAuthorize => scanUserId != null && scanUserId!.isNotEmpty;

  factory ScanLoginRequest.fromJson(Map<String, dynamic> json) {
    final pool = json['connectionPool'];
    final deviceJson =
        pool is Map<String, dynamic>
            ? pool
            : pool is Map
            ? Map<String, dynamic>.from(pool)
            : const <String, dynamic>{};
    final poolDevice = LoginDevice.fromJson(deviceJson);
    return ScanLoginRequest(
      connectionId: json['connectionId']?.toString() ?? '',
      scanUserId: json['scanUserId']?.toString(),
      scanUserName: json['scanUserName']?.toString(),
      state: json['state']?.toString(),
      expiredTime: DateTime.tryParse(json['expiredTime']?.toString() ?? ''),
      device: LoginDevice(
        appName:
            poolDevice.appName ??
            json['scanAppName']?.toString() ??
            json['appName']?.toString(),
        deviceInfo:
            poolDevice.deviceInfo ??
            json['scanDeviceInfo']?.toString() ??
            json['deviceInfo']?.toString(),
        clientId:
            poolDevice.clientId ??
            json['scanClientId']?.toString() ??
            json['clientId']?.toString(),
      ),
    );
  }
}
