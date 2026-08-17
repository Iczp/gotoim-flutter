import '../config/app_environment.dart';
import 'signalr_access_token_reader.dart';
import 'signalr_gateway.dart';
import 'signalr_gateway_stub.dart'
    if (dart.library.io) 'signalr_gateway_io.dart';

SignalRGateway createSignalRGateway({
  required AppEnvironment environment,
  required SignalRAccessTokenReader readAccessToken,
}) {
  return createPlatformSignalRGateway(
    environment: environment,
    readAccessToken: readAccessToken,
  );
}
