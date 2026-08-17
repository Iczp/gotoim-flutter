import '../config/app_environment.dart';
import 'signalr_access_token_reader.dart';
import 'signalr_gateway.dart';

SignalRGateway createPlatformSignalRGateway({
  required AppEnvironment environment,
  required SignalRAccessTokenReader readAccessToken,
}) =>
    UnsupportedSignalRGateway();

class UnsupportedSignalRGateway implements SignalRGateway {
  final Stream<SignalRAppEvent> _events = const Stream<SignalRAppEvent>.empty();

  @override
  SignalRConnectionState get connectionState =>
      SignalRConnectionState.disconnected;

  @override
  Future<void> connect() => Future<void>.error(
        UnsupportedError('SignalR is not configured for this runtime.'),
      );

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() async {}

  @override
  Stream<SignalRAppEvent> get events => _events;

  @override
  Future<T?> invoke<T>(String method, {List<Object>? arguments}) {
    return Future<T?>.error(
      UnsupportedError('SignalR is not configured for this runtime.'),
    );
  }
}
