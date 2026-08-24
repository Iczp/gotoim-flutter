import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/application_providers.dart';
import 'local_file_server.dart';

final localFileServerProvider = Provider<LocalFileServerService>((ref) {
  final service = LocalFileServerService(
    notifications: ref.read(localNotificationServiceProvider),
  );
  ref.onDispose(service.close);
  return service;
});
