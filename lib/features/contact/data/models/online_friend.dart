import 'package:flutter/foundation.dart';

@immutable
class OnlineFriend {
  const OnlineFriend({
    required this.ownerId,
    required this.destinationId,
    required this.sessionId,
    required this.sessionUnitId,
    required this.deviceTypes,
  });

  factory OnlineFriend.fromJson(Map<String, dynamic> json) => OnlineFriend(
    ownerId: _asInt(json['ownerId']) ?? 0,
    destinationId: _asInt(json['destinationId']) ?? 0,
    sessionId: json['sessionId']?.toString() ?? '',
    sessionUnitId: json['sessionUnitId']?.toString() ?? '',
    deviceTypes: (json['deviceTypes'] as List? ?? const <Object?>[])
        .map((value) => value.toString())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false),
  );

  final int ownerId;
  final int destinationId;
  final String sessionId;
  final String sessionUnitId;
  final List<String> deviceTypes;
}

int? _asInt(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value');
