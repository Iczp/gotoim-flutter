import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_file_server.dart';

final localFileServerProvider = Provider<LocalFileServerService>((ref) {
  final service = LocalFileServerService();
  ref.onDispose(service.stop);
  return service;
});
