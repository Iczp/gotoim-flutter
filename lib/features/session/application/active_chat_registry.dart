import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App-wide truth for alert decisions. A chat page registers only while it is
/// visible; transport code must not infer foreground state from SignalR.
class ActiveChatRegistry extends ChangeNotifier {
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  String? _sessionUnitId;

  AppLifecycleState get lifecycle => _lifecycle;
  String? get sessionUnitId => _sessionUnitId;
  bool get isForeground => _lifecycle == AppLifecycleState.resumed;

  bool isForegroundSession(String sessionUnitId) =>
      isForeground && _sessionUnitId == sessionUnitId;

  void updateLifecycle(AppLifecycleState lifecycle) {
    if (_lifecycle == lifecycle) return;
    _lifecycle = lifecycle;
    notifyListeners();
  }

  void enterChat(String sessionUnitId) {
    if (_sessionUnitId == sessionUnitId) return;
    _sessionUnitId = sessionUnitId;
    notifyListeners();
  }

  void leaveChat(String sessionUnitId) {
    if (_sessionUnitId != sessionUnitId) return;
    _sessionUnitId = null;
    notifyListeners();
  }
}

final activeChatRegistryProvider = Provider<ActiveChatRegistry>((ref) {
  final registry = ActiveChatRegistry();
  ref.onDispose(registry.dispose);
  return registry;
});
