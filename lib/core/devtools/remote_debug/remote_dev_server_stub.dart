import 'remote_dev_config.dart';

class RemoteDevServer {
  RemoteDevServer({RemoteDevConfig? config})
      : _config = config ?? const RemoteDevConfig();
  final RemoteDevConfig _config;
  bool get isRunning => false;
  int get port => _config.port;
  int get clientCount => 0;
  String? get url => null;
  Future<void> start() async {}
  Future<void> stop() async {}
}
