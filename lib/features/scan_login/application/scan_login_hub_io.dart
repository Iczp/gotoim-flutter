import 'dart:async';

import 'package:signalr_netcore/signalr_client.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/device/client_device_context.dart';
import 'scan_login_hub.dart';

ScanLoginHub createScanLoginHub({
  required AppEnvironment environment,
  required ClientDeviceContext deviceContext,
  required Future<String> Function() readAccessToken,
}) =>
    _IoScanLoginHub(environment, deviceContext, readAccessToken);

class _IoScanLoginHub implements ScanLoginHub {
  _IoScanLoginHub(
      this._environment, this._deviceContext, this._readAccessToken);

  final AppEnvironment _environment;
  final ClientDeviceContext _deviceContext;
  final Future<String> Function() _readAccessToken;
  final StreamController<ScanLoginHubEvent> _events =
      StreamController<ScanLoginHubEvent>.broadcast();
  HubConnection? _connection;
  Future<void>? _connectInFlight;

  @override
  Stream<ScanLoginHubEvent> get events => _events.stream;

  @override
  Future<void> connect() {
    return _connectInFlight ??= _connect().whenComplete(() {
      _connectInFlight = null;
    });
  }

  Future<void> _connect() async {
    if (_connection?.state == HubConnectionState.Connected) return;
    final previousConnection = _connection;
    _connection = null;
    await previousConnection?.stop();
    late final String accessToken;
    try {
      accessToken = await _readAccessToken();
    } catch (error) {
      throw ScanLoginTokenException(error);
    }
    final url = Uri.parse(_environment.scanLoginHubUrl)
        .replace(queryParameters: <String, String>{
      ...Uri.parse(_environment.scanLoginHubUrl).queryParameters,
      ..._deviceContext.signalRQueryParameters,
    }).toString();
    final connection = HubConnectionBuilder()
        .withUrl(
          url,
          options: HttpConnectionOptions(
            skipNegotiation: _environment.signalRSkipNegotiation,
            transport: HttpTransportType.WebSockets,
            accessTokenFactory: () async => accessToken,
          ),
        )
        .build();
    connection.on('ReceivedMessage', _onReceived);
    _connection = connection;
    await connection.start();
  }

  @override
  Future<ScanLoginChallenge> generate(String state) async {
    final connection = _connection;
    if (connection == null ||
        connection.state != HubConnectionState.Connected) {
      throw StateError('Scan-login connection is not ready.');
    }
    final result = await connection.invoke('Generate', args: <Object>[state]);
    return ScanLoginChallenge.fromJson(_asMap(result));
  }

  void _onReceived(List<Object?>? arguments) {
    final payload =
        _asMap(arguments == null || arguments.isEmpty ? null : arguments.first);
    final command = payload['command']?.toString();
    final body = payload['payload'];
    if (command == null) return;
    _events.add(ScanLoginHubEvent(command, _asMap(body)));
  }

  Map<String, dynamic> _asMap(Object? value) => value is Map
      ? Map<String, dynamic>.from(value)
      : const <String, dynamic>{};

  @override
  Future<void> dispose() async {
    final connection = _connection;
    _connection = null;
    await connection?.stop();
    await _events.close();
  }
}
