import 'package:flutter/foundation.dart';

class RemoteDevConfig {
  const RemoteDevConfig({
    this.enabled = kDebugMode,
    this.port = 18080,
    this.maxMemoryLogs = 5000,
    this.allowRemoteAccess = true,
    this.autoSnapshotOnError = true,
  });

  final bool enabled;
  final int port;
  final int maxMemoryLogs;
  final bool allowRemoteAccess;
  final bool autoSnapshotOnError;
}
