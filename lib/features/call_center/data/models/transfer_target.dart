class TransferTarget {
  const TransferTarget({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.objectType,
    required this.serviceStatusDescription,
  });

  factory TransferTarget.fromJson(Map<String, dynamic> json) => TransferTarget(
    id: _asInt(json['id']) ?? 0,
    name: _firstText(json['displayName'], json['name'], '未命名客服'),
    avatarUrl: _firstText(json['thumbnail'], json['portrait'], ''),
    objectType: _asInt(json['objectType']),
    serviceStatusDescription: _firstText(
      json['serviceStatusDescription'],
      null,
      '',
    ),
  );

  final int id;
  final String name;
  final String avatarUrl;
  final int? objectType;
  final String serviceStatusDescription;

  bool get isShopkeeper => objectType == 7;
  String get roleLabel => isShopkeeper ? '店主' : '客服';
}

int? _asInt(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value');

String _firstText(Object? first, Object? second, String fallback) {
  final firstValue = first?.toString().trim() ?? '';
  if (firstValue.isNotEmpty) return firstValue;
  final secondValue = second?.toString().trim() ?? '';
  return secondValue.isNotEmpty ? secondValue : fallback;
}
