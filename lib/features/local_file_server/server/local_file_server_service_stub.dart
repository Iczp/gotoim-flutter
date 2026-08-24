import 'package:flutter/foundation.dart';

import '../models/local_file_server_state.dart';

class LocalFileServerService extends ChangeNotifier {
  LocalFileServerState _state = const LocalFileServerState.stopped();
  LocalFileServerState get state => _state;

  Future<void> start() async {
    _state = const LocalFileServerState(
      status: LocalFileServerStatus.unsupported,
      error: 'Web 平台无法在设备上监听局域网 HTTP 端口。',
    );
    notifyListeners();
  }

  Future<void> stop() async {}
  Future<void> disconnectTerminal(String terminalId) async {}
}
