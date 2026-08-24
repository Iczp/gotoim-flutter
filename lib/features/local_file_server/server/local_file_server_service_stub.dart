import 'package:flutter/foundation.dart';

import '../../../core/notifications/local_notification_contract.dart';
import '../models/connected_terminal.dart';
import '../models/shared_file.dart';

import '../models/local_file_server_state.dart';

class LocalFileServerService extends ChangeNotifier {
  LocalFileServerService({
    required LocalNotificationService notifications,
    required String shareName,
  });
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
  Future<void> disconnectAllTerminals() async {}
  Future<void> close() => stop();
  List<TerminalActivity> activitiesFor(String terminalId) => const [];
  ConnectedTerminal? terminalFor(String terminalId) => null;
  List<ConnectedTerminal> get recentTerminals => const [];
  Future<List<SharedFile>> listSharedFiles(String path) async => const [];
  Future<void> createSharedDirectory(String parentPath, String name) async {}
  Future<void> renameSharedEntry(String path, String name) async {}
  Future<void> deleteSharedEntry(String path) async {}
  Future<void> openSharedFile(String path) async {}
}
