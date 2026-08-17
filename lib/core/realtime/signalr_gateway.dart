/// Application-level real-time transport boundary.
///
/// Repositories own event-to-database synchronization; UI never listens to a
/// SignalR client directly.
abstract class SignalRGateway {
  Stream<SignalREvent> get events;

  Future<void> connect();

  Future<void> disconnect();

  Future<T?> invoke<T>(String method, {Object? arguments});
}

class SignalREvent {
  const SignalREvent({required this.name, this.payload});

  final String name;
  final Object? payload;
}
