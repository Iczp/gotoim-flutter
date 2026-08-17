/// Cross-device navigation/window contract.
/// Desktop implementations may create or activate a chat window; mobile and
/// tablet implementations navigate in the current window.
abstract class WindowService {
  Future<void> openChat(String sessionId);
}
