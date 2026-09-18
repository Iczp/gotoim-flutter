import '../config/app_environment.dart';
import '../device/client_device_context.dart';
import 'signalr_access_token_reader.dart';
import 'signalr_gateway.dart';

SignalRGateway createPlatformSignalRGateway({
  required AppEnvironment environment,
  required SignalRAccessTokenReader readAccessToken,
  required ClientDeviceContext deviceContext,
}) => UnsupportedSignalRGateway();

class UnsupportedSignalRGateway implements SignalRGateway {
  final Stream<SignalRAppEvent> _events = const Stream<SignalRAppEvent>.empty();

  @override
  SignalRConnectionState get connectionState =>
      SignalRConnectionState.disconnected;

  @override
  Object? get lastError => null;

  @override
  String? get lastErrorDescription => null;

  @override
  SignalRConnectionInfo get connectionInfo => const SignalRConnectionInfo(
    hubUrl: '',
    state: SignalRConnectionState.disconnected,
    connectionId: null,
    keepAliveInterval: Duration.zero,
    serverTimeout: Duration.zero,
  );

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
