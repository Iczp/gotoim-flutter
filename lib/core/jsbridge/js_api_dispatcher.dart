import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import '../capabilities/client_capability_models.dart';
import '../capabilities/client_capability_service.dart';
import '../services/file/file_picker_service.dart';
import '../services/file/file_upload_service.dart';
import '../services/media/media_service.dart';
import '../services/media/video_processing_models.dart';
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
    FileUploadService? uploadService,
    Uuid? uuid,
  }) : _capabilities = capabilities,
       _navigatorProvider = navigatorProvider ?? (() => null),
       _uploadService = uploadService ?? UnsupportedFileUploadService(),
       _uuid = uuid ?? const Uuid() {
    _uploadEventsSubscription = _uploadService.events.listen(
      _forwardUploadEvent,
    );
  }

  static const _maximumImagePayloadBytes = 10 * 1024 * 1024;

  final ClientCapabilityService _capabilities;
  final NavigatorState? Function() _navigatorProvider;
  final FileUploadService _uploadService;
  final Uuid _uuid;
  final StreamController<JsBridgeEvent> _events =
      StreamController<JsBridgeEvent>.broadcast();
  final Map<String, StreamSubscription<ClientNetworkStatus>> _subscriptions =
      <String, StreamSubscription<ClientNetworkStatus>>{};
  final Map<String, String?> _uploadEventSubscriptions = <String, String?>{};
  final Map<String, SelectedFile> _fileReferences = <String, SelectedFile>{};
  late final StreamSubscription<FileUploadEvent> _uploadEventsSubscription;

  Stream<JsBridgeEvent> get events => _events.stream;

  Future<String> handleRaw(String raw) async {
    String id = '';
    try {
      final request = JsBridgeRequest.parse(raw);
      id = request.id;
      return (await dispatch(request)).encode();
    } on FileUploadException catch (error) {
      return JsBridgeResponse.failure(
        id: id,
        error: JsBridgeError(
          code: error.code,
          message: error.message,
          details: error.details,
        ),
      ).encode();
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
    } on FileUploadException catch (error) {
      return JsBridgeResponse.failure(
        id: request.id,
        error: JsBridgeError(
          code: error.code,
          message: error.message,
          details: error.details,
        ),
      );
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
        return <String, Object>{'files': _storeFiles(files)};
      case 'saveFile':
      case 'file.saveFile':
        final bytes = _decodeBase64(_requiredString(request.data, 'base64'));
        final result = await _capabilities.saveFile(
          FileSaveRequest(
            fileName: _requiredString(request.data, 'fileName'),
            bytes: bytes,
            mimeType:
                _optionalString(request.data, 'mimeType') ??
                'application/octet-stream',
            dialogTitle: _optionalString(request.data, 'title'),
            initialDirectory: _optionalString(request.data, 'initialDirectory'),
          ),
        );
        return <String, Object?>{'file': result?.toJson()};
      case 'readFile':
      case 'file.readFile':
        final file = _fileById(request.data);
        final bytes = await file.readBytes();
        _ensurePayloadSize(bytes);
        return <String, Object>{
          'file': file.toJson(),
          'base64': base64Encode(bytes),
        };
      case 'getFileInfo':
      case 'file.getInfo':
        return <String, Object?>{'file': _fileById(request.data).toJson()};
      case 'releaseFile':
      case 'file.release':
        final fileId = _requiredString(request.data, 'fileId');
        final released = _fileReferences.remove(fileId) != null;
        return <String, bool>{'released': released};
      case 'uploadFile':
      case 'file.upload':
        final task = await _uploadService.start(
          _fileById(request.data),
          _uploadRequest(request.data),
        );
        return <String, Object?>{'task': task.toJson()};
      case 'getUploadTask':
      case 'file.getUploadTask':
        final task = _uploadService.task(
          _requiredString(request.data, 'taskId'),
        );
        if (task == null) {
          throw const JsBridgeException('NOT_FOUND', '上传任务不存在或已失效。');
        }
        return <String, Object?>{'task': task.toJson()};
      case 'cancelUpload':
      case 'file.cancelUpload':
        final cancelled = await _uploadService.cancel(
          _requiredString(request.data, 'taskId'),
        );
        return <String, bool>{'cancelled': cancelled};
      case 'onUploadEvent':
      case 'file.onUploadEvent':
        return _subscribeUploadEvents(request.data);
      case 'offUploadEvent':
      case 'file.offUploadEvent':
        return _unsubscribeUploadEvents(request.data);
      case 'clearTemporaryFiles':
      case 'file.clearTemporaryFiles':
        final cleared = await _capabilities.clearTemporaryFiles();
        _fileReferences.clear();
        return <String, bool>{'cleared': cleared};
      case 'chooseImage':
      case 'media.chooseImage':
        final files = await _capabilities.chooseImage(
          _mediaPickRequest(request.data),
        );
        return <String, Object>{'files': _storeFiles(files)};
      case 'takePhoto':
      case 'media.takePhoto':
        final file = await _capabilities.takePhoto(
          _mediaPickRequest(request.data),
        );
        return <String, Object?>{'file': _storeFile(file)};
      case 'chooseVideo':
      case 'media.chooseVideo':
        final file = await _capabilities.chooseVideo(
          _mediaPickRequest(request.data),
        );
        return <String, Object?>{'file': _storeFile(file)};
      case 'recordVideo':
      case 'media.recordVideo':
        final file = await _capabilities.recordVideo(
          _mediaPickRequest(request.data),
        );
        return <String, Object?>{'file': _storeFile(file)};
      case 'compressImage':
      case 'image.compress':
        final output = await _capabilities.compressImage(
          _fileById(request.data),
          ImageCompressionRequest(
            quality: _int(request.data, 'quality', fallback: 85),
            maxWidth: _optionalInt(request.data, 'maxWidth'),
            maxHeight: _optionalInt(request.data, 'maxHeight'),
            format: _imageFormat(request.data['format']),
          ),
        );
        _ensurePayloadSize(output.bytes);
        return <String, Object>{
          'image': output.toJson(),
          'base64': base64Encode(output.bytes),
        };
      case 'getVideoInfo':
      case 'video.getInfo':
        return (await _capabilities.getVideoMetadata(
          _fileById(request.data),
        )).toJson();
      case 'getVideoThumbnail':
      case 'video.getThumbnail':
        final bytes = await _capabilities.createVideoThumbnail(
          _fileById(request.data),
          quality: _int(request.data, 'quality', fallback: 80),
          positionMs: _int(request.data, 'positionMs', fallback: 0),
        );
        _ensurePayloadSize(bytes);
        return <String, Object>{
          'mimeType': 'image/jpeg',
          'base64': base64Encode(bytes),
        };
      case 'compressVideo':
      case 'video.compress':
        final file = await _capabilities.compressVideo(
          _fileById(request.data),
          quality: _videoQuality(request.data['quality']),
          includeAudio: request.data['includeAudio'] != false,
        );
        return <String, Object?>{'file': _storeFile(file)};
      case 'startAudioRecording':
      case 'audio.startRecording':
        await _capabilities.startAudioRecording(
          AudioRecordingRequest(
            fileNamePrefix:
                _optionalString(request.data, 'fileNamePrefix') ??
                'gotoim_recording',
            sampleRate: _int(request.data, 'sampleRate', fallback: 44100),
            bitRate: _int(request.data, 'bitRate', fallback: 128000),
            numChannels: _int(request.data, 'numChannels', fallback: 1),
          ),
        );
        return const <String, bool>{'started': true};
      case 'pauseAudioRecording':
      case 'audio.pauseRecording':
        await _capabilities.pauseAudioRecording();
        return const <String, bool>{'paused': true};
      case 'resumeAudioRecording':
      case 'audio.resumeRecording':
        await _capabilities.resumeAudioRecording();
        return const <String, bool>{'resumed': true};
      case 'stopAudioRecording':
      case 'audio.stopRecording':
        final file = await _capabilities.stopAudioRecording();
        return <String, Object?>{'file': _storeFile(file)};
      case 'cancelAudioRecording':
      case 'audio.cancelRecording':
        await _capabilities.cancelAudioRecording();
        return const <String, bool>{'cancelled': true};
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
      case 'scan.decodeImage':
        final fileId = _optionalString(request.data, 'fileId');
        final bytes =
            fileId == null
                ? _decodeBase64(_requiredString(request.data, 'base64'))
                : await _fileById(request.data).readBytes();
        _ensurePayloadSize(bytes);
        final result = await _capabilities.decodeImage(
          DecodeImageRequest(
            bytes: bytes,
            formats: _scanFormats(request.data['formats']),
          ),
        );
        return <String, Object?>{'result': _scanResult(result)};
      case 'scanCodeFromImage':
      case 'scan.chooseImageAndDecode':
        final files = await _capabilities.chooseImage(
          _mediaPickRequest(request.data),
        );
        if (files.isEmpty) {
          return const <String, Object?>{'file': null, 'result': null};
        }
        final file = files.first;
        _storeFile(file);
        final result = await _capabilities.decodeImageFile(
          file,
          formats: _scanFormats(request.data['formats']),
        );
        return <String, Object?>{
          'file': file.toJson(),
          'result': _scanResult(result),
        };
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

  Map<String, String?> _subscribeUploadEvents(Map<String, dynamic> data) {
    final subscriptionId =
        _optionalString(data, 'subscriptionId') ?? _uuid.v4();
    final taskId = _optionalString(data, 'taskId');
    if (taskId != null && _uploadService.task(taskId) == null) {
      throw const JsBridgeException('NOT_FOUND', '上传任务不存在或已失效。');
    }
    _uploadEventSubscriptions[subscriptionId] = taskId;
    return <String, String?>{
      'subscriptionId': subscriptionId,
      'taskId': taskId,
    };
  }

  Map<String, Object> _unsubscribeUploadEvents(Map<String, dynamic> data) {
    final subscriptionId = _requiredString(data, 'subscriptionId');
    final removed = _uploadEventSubscriptions.remove(subscriptionId) != null;
    return <String, Object>{'removed': removed};
  }

  void _forwardUploadEvent(FileUploadEvent event) {
    for (final entry in _uploadEventSubscriptions.entries) {
      final taskId = entry.value;
      if (taskId != null && taskId != event.task.taskId) continue;
      _events.add(
        JsBridgeEvent(
          name: event.name,
          data: <String, Object?>{
            'subscriptionId': entry.key,
            ...event.toJson(),
          },
        ),
      );
    }
  }

  Future<void> dispose() async {
    for (final subscription in _subscriptions.values) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _uploadEventSubscriptions.clear();
    await _uploadEventsSubscription.cancel();
    _fileReferences.clear();
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

  Map<String, String> _stringMap(Object? value, {required String name}) {
    if (value == null) return const <String, String>{};
    if (value is! Map) {
      throw JsBridgeException('INVALID_ARGUMENT', '$name 必须是对象。');
    }
    final result = <String, String>{};
    for (final entry in value.entries) {
      if (entry.key is! String || entry.key.trim().isEmpty) {
        throw JsBridgeException('INVALID_ARGUMENT', '$name 的键必须是非空字符串。');
      }
      final item = entry.value;
      if (item is! String && item is! num && item is! bool) {
        throw JsBridgeException('INVALID_ARGUMENT', '$name 的值必须是字符串、数字或布尔值。');
      }
      result[entry.key] = '$item';
    }
    return result;
  }

  FileUploadRequest _uploadRequest(Map<String, dynamic> data) {
    final rawUrl = _requiredString(data, 'uploadUrl');
    final url = Uri.tryParse(rawUrl);
    if (url == null || !url.hasScheme) {
      throw const JsBridgeException('INVALID_ARGUMENT', 'uploadUrl 不是有效地址。');
    }
    final method = (_optionalString(data, 'method') ?? 'POST').toUpperCase();
    final timeoutSeconds = _optionalInt(data, 'timeoutSeconds') ?? 60;
    if (timeoutSeconds < 5 || timeoutSeconds > 600) {
      throw const JsBridgeException(
        'INVALID_ARGUMENT',
        'timeoutSeconds 必须在 5 到 600 之间。',
      );
    }
    return FileUploadRequest(
      uploadUrl: url,
      method: method,
      multipart: data['multipart'] != false,
      fieldName: _optionalString(data, 'fieldName') ?? 'file',
      headers: _stringMap(data['headers'], name: 'headers'),
      formData: _stringMap(data['formData'], name: 'formData'),
      timeout: Duration(seconds: timeoutSeconds),
    );
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

  List<Map<String, Object?>> _storeFiles(List<SelectedFile> files) =>
      files.map(_storeFile).whereType<Map<String, Object?>>().toList();

  Map<String, Object?>? _storeFile(SelectedFile? file) {
    if (file == null) return null;
    _fileReferences[file.id] = file;
    return file.toJson();
  }

  SelectedFile _fileById(Map<String, dynamic> data) {
    final fileId = _requiredString(data, 'fileId');
    final file = _fileReferences[fileId];
    if (file == null) {
      throw const JsBridgeException('NOT_FOUND', '文件引用已失效，请重新选择文件。');
    }
    return file;
  }

  Uint8List _decodeBase64(String raw) {
    try {
      final bytes = base64Decode(_stripDataUrlPrefix(raw));
      _ensurePayloadSize(bytes);
      return bytes;
    } on FormatException {
      throw const JsBridgeException('INVALID_ARGUMENT', 'base64 不是有效数据。');
    }
  }

  void _ensurePayloadSize(Uint8List bytes) {
    if (bytes.lengthInBytes > _maximumImagePayloadBytes) {
      throw const JsBridgeException('PAYLOAD_TOO_LARGE', '二进制数据不能超过 10 MiB。');
    }
  }

  MediaPickRequest _mediaPickRequest(Map<String, dynamic> data) =>
      MediaPickRequest(
        allowMultiple: data['allowMultiple'] == true,
        preserveOriginal: data['preserveOriginal'] != false,
        imageQuality: _optionalInt(data, 'imageQuality'),
        maxWidth: _optionalDouble(data, 'maxWidth'),
        maxHeight: _optionalDouble(data, 'maxHeight'),
        maxDuration:
            _optionalInt(data, 'maxDurationSeconds') == null
                ? null
                : Duration(seconds: _optionalInt(data, 'maxDurationSeconds')!),
      );

  int _int(Map<String, dynamic> data, String key, {required int fallback}) =>
      _optionalInt(data, key) ?? fallback;

  int? _optionalInt(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value == null) return null;
    if (value is int) return value;
    if (value is num && value == value.roundToDouble()) return value.toInt();
    throw JsBridgeException('INVALID_ARGUMENT', '$key 必须是整数。');
  }

  double? _optionalDouble(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value == null) return null;
    if (value is num) return value.toDouble();
    throw JsBridgeException('INVALID_ARGUMENT', '$key 必须是数字。');
  }

  ImageOutputFormat _imageFormat(Object? value) => switch (value) {
    null || 'jpeg' || 'jpg' => ImageOutputFormat.jpeg,
    'png' => ImageOutputFormat.png,
    'webp' => ImageOutputFormat.webp,
    _ =>
      throw const JsBridgeException(
        'INVALID_ARGUMENT',
        'format 仅支持 jpeg、png、webp。',
      ),
  };

  VideoCompressionQuality _videoQuality(Object? value) => switch (value) {
    null || 'medium' => VideoCompressionQuality.medium,
    'low' => VideoCompressionQuality.low,
    'high' => VideoCompressionQuality.high,
    'original' => VideoCompressionQuality.original,
    _ =>
      throw const JsBridgeException(
        'INVALID_ARGUMENT',
        'quality 仅支持 low、medium、high、original。',
      ),
  };

  String _stripDataUrlPrefix(String value) {
    final marker = value.indexOf(',');
    return value.startsWith('data:') && marker >= 0
        ? value.substring(marker + 1)
        : value;
  }
}
