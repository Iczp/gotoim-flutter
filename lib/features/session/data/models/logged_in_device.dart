class LoggedInDevice {
  const LoggedInDevice({
    required this.deviceId,
    required this.deviceType,
    required this.brand,
    required this.model,
    required this.updatedAt,
    required this.groups,
  });

  factory LoggedInDevice.fromJson(Map<String, dynamic> json) => LoggedInDevice(
    deviceId: json['deviceId']?.toString() ?? '',
    deviceType: json['deviceType']?.toString() ?? '',
    brand: (json['deviceBrand'] ?? json['brand'] ?? '').toString(),
    model: (json['deviceModel'] ?? json['model'] ?? '').toString(),
    updatedAt:
        DateTime.tryParse(
          (json['lastModificationTime'] ?? json['creationTime'] ?? '')
              .toString(),
        )?.toLocal(),
    groups: (json['groups'] is List ? json['groups'] as List : const [])
        .whereType<Map>()
        .map((group) => group['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toList(growable: false),
  );

  final String deviceId;
  final String deviceType;
  final String brand;
  final String model;
  final DateTime? updatedAt;
  final List<String> groups;
}
