class LoggedInDevice {
  const LoggedInDevice({
    required this.connectionId,
    required this.deviceId,
    required this.deviceType,
    required this.brand,
    required this.model,
    required this.updatedAt,
    required this.groups,
    required this.ipAddress,
    required this.host,
    required this.browser,
    required this.browserInfo,
    required this.platform,
    this.chatObjectIdList = const <int>[],
  });

  factory LoggedInDevice.fromJson(Map<String, dynamic> json) => LoggedInDevice(
    connectionId: json['connectionId']?.toString() ?? '',
    deviceId: json['deviceId']?.toString() ?? '',
    deviceType: json['deviceType']?.toString() ?? '',
    brand: (json['deviceBrand'] ?? json['brand'] ?? '').toString(),
    model: (json['deviceModel'] ?? json['model'] ?? '').toString(),
    updatedAt:
        DateTime.tryParse(
          (json['activeTime'] ??
                  json['lastModificationTime'] ??
                  json['creationTime'] ??
                  '')
              .toString(),
        )?.toLocal(),
    groups: (json['groups'] is List ? json['groups'] as List : const [])
        .whereType<Map>()
        .map((group) => group['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toList(growable: false),
    ipAddress: json['ipAddress']?.toString() ?? '',
    host: json['host']?.toString() ?? '',
    browser: json['browser']?.toString() ?? '',
    browserInfo: json['browserInfo']?.toString() ?? '',
    platform: json['platform']?.toString() ?? '',
    chatObjectIdList: (json['chatObjectIdList'] is List
        ? (json['chatObjectIdList'] as List)
            .map((e) => e is num ? e.toInt() : int.tryParse('$e'))
            .whereType<int>()
            .toList(growable: false)
        : const <int>[]),
  );

  final String deviceId;

  /// SignalR connection identifier; required by the online abort endpoint.
  final String connectionId;
  final String deviceType;
  final String brand;
  final String model;
  final DateTime? updatedAt;
  final List<String> groups;
  final String ipAddress;
  final String host;
  final String browser;
  final String browserInfo;
  final String platform;
  final List<int> chatObjectIdList;
}
