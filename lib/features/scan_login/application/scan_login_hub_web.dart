// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import '../../../core/config/app_environment.dart';
import '../../../core/device/client_device_context.dart';
import 'scan_login_hub.dart';

ScanLoginHub createScanLoginHub({
  required AppEnvironment environment,
  required ClientDeviceContext deviceContext,
  required Future<String> Function() readAccessToken,
}) => _WebScanLoginHub(environment, deviceContext, readAccessToken);

class _WebScanLoginHub implements ScanLoginHub {
  _WebScanLoginHub(
    this._environment,
    this._deviceContext,
    this._readAccessToken,
  );

  final AppEnvironment _environment;
  final ClientDeviceContext _deviceContext;
  final Future<String> Function() _readAccessToken;
  final StreamController<ScanLoginHubEvent> _events =
      StreamController<ScanLoginHubEvent>.broadcast();
  JSObject? _connection;

  @override
  Stream<ScanLoginHubEvent> get events => _events.stream;

  @override
  Future<void> connect() async {
    if (_connection != null) return;
    final signalR = globalContext['signalR'];
    if (signalR == null || !signalR.isA<JSObject>()) {
      throw UnsupportedError('SignalR web client was not loaded.');
    }
    final signalRObject = signalR as JSObject;
    late final String accessToken;
    try {
      accessToken = await _readAccessToken();
    } catch (error) {
      throw ScanLoginTokenException(error);
    }
    final uri = Uri.parse(_environment.scanLoginHubUrl).replace(
      queryParameters: <String, String>{
        ...Uri.parse(_environment.scanLoginHubUrl).queryParameters,
        ..._deviceContext.signalRQueryParameters,
      },
    );
    final builderConstructor = signalRObject['HubConnectionBuilder'];
    final transportTypes = signalRObject['HttpTransportType'];
    if (builderConstructor == null ||
        !builderConstructor.isA<JSFunction>() ||
        transportTypes == null ||
        !transportTypes.isA<JSObject>()) {
      throw UnsupportedError('SignalR web client is incomplete.');
    }
    final builderFunction = builderConstructor as JSFunction;
    final transportTypeObject = transportTypes as JSObject;
    final options =
        <String, Object?>{
              'skipNegotiation': _environment.signalRSkipNegotiation,
              'accessTokenFactory': (() => accessToken.toJS).toJS,
            }.jsify()!
            as JSObject;
    options['transport'] = transportTypeObject['WebSockets'];
    final builder = builderFunction.callAsConstructor<JSObject>();
    final configured = builder.callMethod<JSObject>(
      'withUrl'.toJS,
      uri.toString().toJS,
      options,
    );
    _connection = configured.callMethod<JSObject>('build'.toJS);
    _connection!.callMethod<JSAny?>(
      'on'.toJS,
      'ReceivedMessage'.toJS,
      ((JSAny? message) {
        final envelope = _mapJs(message);
        final command = envelope['command']?.toString();
        if (command != null) {
          _events.add(
            ScanLoginHubEvent(command, _mapDart(envelope['payload'])),
          );
        }
      }).toJS,
    );
    await _connection!.callMethod<JSPromise<JSAny?>>('start'.toJS).toDart;
  }

  @override
  Future<ScanLoginChallenge> generate(String state) async {
    final connection = _connection;
    if (connection == null) {
      throw StateError('Scan-login connection is not ready.');
    }
    final result =
        await connection
            .callMethod<JSPromise<JSAny?>>(
              'invoke'.toJS,
              'Generate'.toJS,
              state.toJS,
            )
            .toDart;
    return ScanLoginChallenge.fromJson(_mapJs(result));
  }

  Map<String, dynamic> _mapJs(JSAny? value) => _mapDart(value?.dartify());

  Map<String, dynamic> _mapDart(Object? dartValue) {
    return dartValue is Map ? Map<String, dynamic>.from(dartValue) : const {};
  }

  @override
  Future<void> dispose() async {
    if (_connection != null) {
      await _connection!.callMethod<JSPromise<JSAny?>>('stop'.toJS).toDart;
    }
    _connection = null;
    await _events.close();
  }
}
