import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/application_providers.dart';
import '../../core/device/client_device_context.dart';
import 'local_file_server.dart';

final localFileServerProvider = Provider<LocalFileServerService>((ref) {
  final service = LocalFileServerService(
    notifications: ref.read(localNotificationServiceProvider),
    shareName: ref.read(clientDeviceContextProvider).appName,
  );
  ref.onDispose(service.close);
  return service;
});
