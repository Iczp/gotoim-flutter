// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:js' as js;
import 'dart:js_util' as js_util;

import '../../../core/config/app_environment.dart';
import '../../../core/device/client_device_context.dart';
import 'scan_login_hub.dart';

ScanLoginHub createScanLoginHub({
  required AppEnvironment environment,
  required ClientDeviceContext deviceContext,
  required Future<String> Function() readAccessToken,
}) =>
    _WebScanLoginHub(environment, deviceContext, readAccessToken);

class _WebScanLoginHub implements ScanLoginHub {
  _WebScanLoginHub(
      this._environment, this._deviceContext, this._readAccessToken);

  final AppEnvironment _environment;
  final ClientDeviceContext _deviceContext;
  final Future<String> Function() _readAccessToken;
  final StreamController<ScanLoginHubEvent> _events =
      StreamController<ScanLoginHubEvent>.broadcast();
  Object? _connection;

  @override
  Stream<ScanLoginHubEvent> get events => _events.stream;

  @override
  Future<void> connect() async {
    if (_connection != null) return;
    final signalR = js.context['signalR'];
    if (signalR == null) {
      throw UnsupportedError('SignalR web client was not loaded.');
    }
    final accessToken = await _readAccessToken();
    final uri = Uri.parse(_environment.scanLoginHubUrl).replace(
      queryParameters: <String, String>{
        ...Uri.parse(_environment.scanLoginHubUrl).queryParameters,
        ..._deviceContext.signalRQueryParameters,
      },
    );
    final builder = js_util.callConstructor(
      js_util.getProperty(signalR, 'HubConnectionBuilder'),
      const <Object>[],
    );
    final configured = js_util.callMethod(builder, 'withUrl', <Object>[
      uri.toString(),
      js_util.jsify(<String, Object>{
        'skipNegotiation': _environment.signalRSkipNegotiation,
        'transport': js_util.getProperty(
          js_util.getProperty(signalR, 'HttpTransportType'),
          'WebSockets',
        ),
        'accessTokenFactory': js.allowInterop(() => accessToken),
      }),
    ]);
    _connection = js_util.callMethod(configured, 'build', const <Object>[]);
    js_util.callMethod(_connection!, 'on', <Object>[
      'ReceivedMessage',
      js.allowInterop((Object? message) {
        final envelope = _map(message);
        final command = envelope['command']?.toString();
        if (command != null) {
          _events.add(ScanLoginHubEvent(command, _map(envelope['payload'])));
        }
      }),
    ]);
    await js_util.promiseToFuture<void>(
      js_util.callMethod(_connection!, 'start', const <Object>[]),
    );
  }

  @override
  Future<ScanLoginChallenge> generate(String state) async {
    final connection = _connection;
    if (connection == null) {
      throw StateError('Scan-login connection is not ready.');
    }
    final result = await js_util.promiseToFuture<Object?>(
      js_util.callMethod(connection, 'invoke', <Object>['Generate', state]),
    );
    return ScanLoginChallenge.fromJson(_map(result));
  }

  Map<String, dynamic> _map(Object? value) {
    final dartValue = js_util.dartify(value);
    return dartValue is Map ? Map<String, dynamic>.from(dartValue) : const {};
  }

  @override
  Future<void> dispose() async {
    if (_connection != null) {
      await js_util.promiseToFuture<void>(
        js_util.callMethod(_connection!, 'stop', const <Object>[]),
      );
    }
    _connection = null;
    await _events.close();
  }
}
