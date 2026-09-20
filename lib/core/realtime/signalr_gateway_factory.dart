import 'dart:async';

import '../config/app_environment.dart';
import '../device/client_device_context.dart';
import 'signalr_access_token_reader.dart';
import 'signalr_gateway.dart';
import 'signalr_gateway_stub.dart'
    if (dart.library.io) 'signalr_gateway_io.dart';

SignalRGateway createSignalRGateway({
  required AppEnvironment environment,
  required SignalRAccessTokenReader readAccessToken,
  required ClientDeviceContext deviceContext,
  Future<String?> Function()? refreshToken,
  FutureOr<void> Function()? onSessionInvalidated,
}) {
  return createPlatformSignalRGateway(
    environment: environment,
    readAccessToken: readAccessToken,
    deviceContext: deviceContext,
    refreshToken: refreshToken,
    onSessionInvalidated: onSessionInvalidated,
  );
}
