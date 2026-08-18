import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/device/client_device_context.dart';
import '../../auth/application/auth_controller.dart';

import 'scan_login_hub_stub.dart'
    if (dart.library.io) 'scan_login_hub_io.dart'
    if (dart.library.html) 'scan_login_hub_web.dart' as platform;

abstract class ScanLoginHub {
  Stream<ScanLoginHubEvent> get events;

  Future<void> connect();

  Future<ScanLoginChallenge> generate(String state);

  Future<void> dispose();
}

class ScanLoginChallenge {
  const ScanLoginChallenge({required this.scanText, required this.expiredTime});

  final String scanText;
  final DateTime? expiredTime;

  factory ScanLoginChallenge.fromJson(Map<String, dynamic> json) =>
      ScanLoginChallenge(
        scanText: json['scanText']?.toString() ?? '',
        expiredTime: DateTime.tryParse(json['expiredTime']?.toString() ?? ''),
      );
}

class ScanLoginHubEvent {
  const ScanLoginHubEvent(this.command, this.payload);

  final String command;
  final Map<String, dynamic> payload;

  String? get scanToken => payload['scanToken']?.toString();
}

final scanLoginHubProvider = Provider.autoDispose<ScanLoginHub>((ref) {
  final environment = ref.watch(appEnvironmentProvider);
  final device = ref.watch(clientDeviceContextProvider);
  final repository = ref.watch(authRepositoryProvider);
  final hub = platform.createScanLoginHub(
    environment: environment,
    deviceContext: device,
    readAccessToken: repository.getClientCredentialsAccessToken,
  );
  ref.onDispose(hub.dispose);
  return hub;
});
