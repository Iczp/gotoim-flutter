import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import '../capabilities/client_capability_models.dart';
import '../capabilities/client_capability_service.dart';
import '../services/file/file_picker_service.dart';
import '../services/scan/scan_code_service.dart';
import 'js_bridge_models.dart';

/// Dispatches JSON bridge requests to application-owned capability services.
///
/// It has no WebView dependency. A WebView adapter only needs to forward its
/// JavaScript channel messages to [handleRaw] and subscribe to [events].
class JsApiDispatcher {
  JsApiDispatcher({
    required ClientCapabilityService capabilities,
    NavigatorState? Function()? navigatorProvider,
    Uuid? uuid,
  }) : _capabilities = capabilities,
       _navigatorProvider = navigatorProvider ?? (() => null),
       _uuid = uuid ?? const Uuid();

  static const _maximumImagePayloadBytes = 10 * 1024 * 1024;

  final ClientCapabilityService _capabilities;
  final NavigatorState? Function() _navigatorProvider;
  final Uuid _uuid;
  final StreamController<JsBridgeEvent> _events =
      StreamController<JsBridgeEvent>.broadcast();
  final Map<String, StreamSubscription<ClientNetworkStatus>> _subscriptions =
      <String, StreamSubscription<ClientNetworkStatus>>{};

  Stream<JsBridgeEvent> get events => _events.stream;

  Future<String> handleRaw(String raw) async {
    String id = '';
    try {
      final request = JsBridgeRequest.parse(raw);
      id = request.id;
      return (await dispatch(request)).encode();
    } on JsBridgeException catch (error) {
      return JsBridgeResponse.failure(
        id: id,
        error: JsBridgeError(
          code: error.code,
          message: error.message,
          details: error.details,
        ),
      ).encode();
    } on FormatException catch (error) {
      return JsBridgeResponse.failure(
        id: id,
        error: JsBridgeError(code: 'INVALID_REQUEST', message: error.message),
      ).encode();
    } catch (error) {
      return JsBridgeResponse.failure(
        id: id,
        error: JsBridgeError(code: 'INTERNAL_ERROR', message: '$error'),
      ).encode();
    }
  }

  Future<JsBridgeResponse> dispatch(JsBridgeRequest request) async {
    try {
      final data = await _invoke(request);
      return JsBridgeResponse.success(id: request.id, data: data);
    } on JsBridgeException catch (error) {
      return JsBridgeResponse.failure(
        id: request.id,
        error: JsBridgeError(
          code: error.code,
          message: error.message,
          details: error.details,
        ),
      );
    } catch (error) {
      return JsBridgeResponse.failure(
        id: request.id,
        error: JsBridgeError(code: 'INTERNAL_ERROR', message: '$error'),
      );
    }
  }

  Future<Object?> _invoke(JsBridgeRequest request) async {
    switch (request.action) {
      case 'getSystemInfo':
      case 'system.getSystemInfo':
        return (await _capabilities.getSystemInfo()).toJson();
      case 'getDeviceInfo':
      case 'device.getDeviceInfo':
        return (await _capabilities.getDeviceInfo()).toJson();
      case 'getNetworkType':
      case 'network.getNetworkType':
        return (await _capabilities.getNetworkType()).toJson();
      case 'onNetworkStatusChange':
      case 'network.onStatusChange':
        return _subscribeNetworkStatus(request.data);
      case 'offNetworkStatusChange':
      case 'network.offStatusChange':
        return _unsubscribeNetworkStatus(request.data);
      case 'getCapabilities':
      case 'capabilities.get':
        final supports = await _capabilities.getCapabilities();
        return <String, Object>{
          'capabilities': supports.map((item) => item.toJson()).toList(),
        };
      case 'setClipboardData':
      case 'clipboard.setData':
        final value = _requiredString(request.data, 'data');
        await _capabilities.setClipboardData(value);
        return const <String, bool>{'ok': true};
      case 'getClipboardData':
      case 'clipboard.getData':
        return <String, String?>{
          'data': await _capabilities.getClipboardData(),
        };
      case 'chooseFile':
      case 'file.chooseFile':
        final files = await _capabilities.chooseFile(
          FilePickerRequest(
            allowMultiple: request.data['allowMultiple'] == true,
            allowedExtensions: _stringList(request.data['allowedExtensions']),
            dialogTitle: _optionalString(request.data, 'title'),
          ),
        );
        return <String, Object>{
          'files': files.map((item) => item.toJson()).toList(),
        };
      case 'scanCode':
      case 'scan.scanCode':
        final navigator = _navigatorProvider();
        if (navigator == null) {
          throw const JsBridgeException(
            'UNAVAILABLE',
            '当前没有可用于打开扫码页的 Navigator。',
          );
        }
        final result = await _capabilities.scanCode(
          navigator,
          ScanCodeRequest(
            formats: _scanFormats(request.data['formats']),
            title: _optionalString(request.data, 'title') ?? '扫一扫',
            tip: _optionalString(request.data, 'tip') ?? '将二维码或条形码放入框内，即可自动扫描',
            allowAlbum: request.data['allowAlbum'] != false,
            allowTorch: request.data['allowTorch'] != false,
          ),
        );
        return <String, Object?>{'result': _scanResult(result)};
      case 'decodeImage':
      case 'image.decodeImage':
        final raw = _requiredString(request.data, 'base64');
        Uint8List bytes;
        try {
          bytes = base64Decode(_stripDataUrlPrefix(raw));
        } on FormatException {
          throw const JsBridgeException('INVALID_ARGUMENT', 'base64 不是有效图片数据。');
        }
        if (bytes.lengthInBytes > _maximumImagePayloadBytes) {
          throw const JsBridgeException(
            'PAYLOAD_TOO_LARGE',
            '图片数据不能超过 10 MiB。',
          );
        }
        final result = await _capabilities.decodeImage(
          DecodeImageRequest(
            bytes: bytes,
            formats: _scanFormats(request.data['formats']),
          ),
        );
        return <String, Object?>{'result': _scanResult(result)};
      case 'notification.getSupport':
        final support = _capabilities.notificationSupport;
        return <String, Object>{
          'platform': support.platform.name,
          'isSupported': support.isSupported,
          'message': support.message,
        };
      case 'notification.requestPermission':
        final permission = await _capabilities.requestNotificationPermission();
        return <String, String>{
          'status': permission.status.name,
          'message': permission.message,
        };
      default:
        throw JsBridgeException(
          'NOT_SUPPORTED',
          '未支持的 action：${request.action}',
        );
    }
  }

  Map<String, String> _subscribeNetworkStatus(Map<String, dynamic> data) {
    final subscriptionId =
        _optionalString(data, 'subscriptionId') ?? _uuid.v4();
    _subscriptions.remove(subscriptionId)?.cancel();
    _subscriptions[subscriptionId] = _capabilities.networkStatusChanges.listen((
      networkStatus,
    ) {
      _events.add(
        JsBridgeEvent(
          name: 'network.statusChange',
          data: <String, Object?>{
            'subscriptionId': subscriptionId,
            'status': networkStatus.toJson(),
          },
        ),
      );
    });
    return <String, String>{'subscriptionId': subscriptionId};
  }

  Map<String, Object> _unsubscribeNetworkStatus(Map<String, dynamic> data) {
    final subscriptionId = _requiredString(data, 'subscriptionId');
    final removed = _subscriptions.remove(subscriptionId);
    removed?.cancel();
    return <String, Object>{'removed': removed != null};
  }

  Future<void> dispose() async {
    for (final subscription in _subscriptions.values) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _events.close();
  }

  String _requiredString(Map<String, dynamic> data, String key) {
    final value = _optionalString(data, key);
    if (value == null) {
      throw JsBridgeException('INVALID_ARGUMENT', '$key 必须是非空字符串。');
    }
    return value;
  }

  String? _optionalString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value == null) return null;
    if (value is! String) {
      throw JsBridgeException('INVALID_ARGUMENT', '$key 必须是字符串。');
    }
    return value.trim().isEmpty ? null : value;
  }

  List<String> _stringList(Object? value) {
    if (value == null) return const <String>[];
    if (value is! List || value.any((item) => item is! String)) {
      throw const JsBridgeException('INVALID_ARGUMENT', '列表参数必须是字符串数组。');
    }
    return value.cast<String>();
  }

  List<ScanCodeFormat> _scanFormats(Object? value) {
    final names = _stringList(value);
    if (names.isEmpty) return const <ScanCodeFormat>[];
    final formats = <ScanCodeFormat>[];
    for (final name in names) {
      final format =
          ScanCodeFormat.values.where((item) => item.name == name).firstOrNull;
      if (format == null) {
        throw JsBridgeException('INVALID_ARGUMENT', '不支持的码制：$name');
      }
      formats.add(format);
    }
    return formats;
  }

  Map<String, Object?>? _scanResult(ScanCodeResult? result) =>
      result == null
          ? null
          : <String, Object?>{
            'content': result.content,
            'format': result.format?.name,
            'source': result.source.name,
          };

  String _stripDataUrlPrefix(String value) {
    final marker = value.indexOf(',');
    return value.startsWith('data:') && marker >= 0
        ? value.substring(marker + 1)
        : value;
  }
}
