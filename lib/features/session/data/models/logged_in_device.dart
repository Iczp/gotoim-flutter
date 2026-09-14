class LoggedInDevice {
  const LoggedInDevice({
    required this.connectionId,
    required this.deviceId,
    required this.deviceType,
    required this.brand,
    required this.model,
    required this.updatedAt,
    required this.groups,
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
  );

  final String deviceId;

  /// SignalR connection identifier; required by the online abort endpoint.
  final String connectionId;
  final String deviceType;
  final String brand;
  final String model;
  final DateTime? updatedAt;
  final List<String> groups;
}
