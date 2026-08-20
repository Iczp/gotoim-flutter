import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import 'file_picker_service.dart';

enum FileUploadState { queued, uploading, completed, failed, cancelled }

class FileUploadRequest {
  const FileUploadRequest({
    required this.uploadUrl,
    this.method = 'POST',
    this.multipart = true,
    this.fieldName = 'file',
    this.headers = const <String, String>{},
    this.formData = const <String, String>{},
    this.timeout = const Duration(seconds: 60),
  });

  final Uri uploadUrl;
  final String method;
  final bool multipart;
  final String fieldName;
  final Map<String, String> headers;
  final Map<String, String> formData;
  final Duration timeout;
}

class FileUploadTask {
  const FileUploadTask({
    required this.taskId,
    required this.fileId,
    required this.state,
    required this.sentBytes,
    required this.totalBytes,
    this.response,
    this.error,
  });

  final String taskId;
  final String fileId;
  final FileUploadState state;
  final int sentBytes;
  final int totalBytes;
  final Map<String, Object?>? response;
  final Map<String, Object?>? error;

  double get progress => totalBytes == 0 ? 0 : sentBytes / totalBytes;

  FileUploadTask copyWith({
    FileUploadState? state,
    int? sentBytes,
    int? totalBytes,
    Map<String, Object?>? response,
    Map<String, Object?>? error,
  }) => FileUploadTask(
    taskId: taskId,
    fileId: fileId,
    state: state ?? this.state,
    sentBytes: sentBytes ?? this.sentBytes,
    totalBytes: totalBytes ?? this.totalBytes,
    response: response ?? this.response,
    error: error ?? this.error,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'taskId': taskId,
    'fileId': fileId,
    'state': state.name,
    'sentBytes': sentBytes,
    'totalBytes': totalBytes,
    'progress': progress,
    if (response != null) 'response': response,
    if (error != null) 'error': error,
  };
}

class FileUploadEvent {
  const FileUploadEvent({required this.name, required this.task});

  final String name;
  final FileUploadTask task;

  Map<String, Object?> toJson() => task.toJson();
}

class FileUploadException implements Exception {
  const FileUploadException(this.code, this.message, {this.details});

  final String code;
  final String message;
  final Object? details;
}

/// Uploads an app-held [SelectedFile] without exposing its bytes or native
/// path to JavaScript. A task persists for the app session and reports events.
abstract class FileUploadService {
  Stream<FileUploadEvent> get events;

  Future<FileUploadTask> start(SelectedFile file, FileUploadRequest request);

  FileUploadTask? task(String taskId);

  Future<bool> cancel(String taskId);

  Future<void> dispose();
}

class DioFileUploadService implements FileUploadService {
  DioFileUploadService({
    Dio? dio,
    Iterable<String> allowedHosts = const <String>[],
    Uuid? uuid,
  }) : _dio = dio ?? Dio(),
       _allowedHosts =
           allowedHosts
               .map((host) => host.trim().toLowerCase())
               .where((host) => host.isNotEmpty)
               .toSet(),
       _uuid = uuid ?? const Uuid();

  final Dio _dio;
  final Set<String> _allowedHosts;
  final Uuid _uuid;
  final StreamController<FileUploadEvent> _events =
      StreamController<FileUploadEvent>.broadcast();
  final Map<String, FileUploadTask> _tasks = <String, FileUploadTask>{};
  final Map<String, CancelToken> _cancelTokens = <String, CancelToken>{};
  final Map<String, DateTime> _lastProgressAt = <String, DateTime>{};

  @override
  Stream<FileUploadEvent> get events => _events.stream;

  @override
  Future<FileUploadTask> start(
    SelectedFile file,
    FileUploadRequest request,
  ) async {
    _validateRequest(request);
    final task = FileUploadTask(
      taskId: _uuid.v4(),
      fileId: file.id,
      state: FileUploadState.queued,
      sentBytes: 0,
      totalBytes: file.size,
    );
    _tasks[task.taskId] = task;
    _emit('file.uploadQueued', task);
    unawaited(_upload(task.taskId, file, request));
    return task;
  }

  @override
  FileUploadTask? task(String taskId) => _tasks[taskId];

  @override
  Future<bool> cancel(String taskId) async {
    final token = _cancelTokens[taskId];
    final current = _tasks[taskId];
    if (current == null || _isTerminal(current.state)) return false;
    token?.cancel('Cancelled by JS Bridge');
    if (token == null) {
      _setTask(current.copyWith(state: FileUploadState.cancelled));
      _emit('file.uploadCancelled', _tasks[taskId]!);
    }
    return true;
  }

  Future<void> _upload(
    String taskId,
    SelectedFile file,
    FileUploadRequest request,
  ) async {
    final token = CancelToken();
    _cancelTokens[taskId] = token;
    _setTask(_tasks[taskId]!.copyWith(state: FileUploadState.uploading));
    try {
      final response = await _dio.request<dynamic>(
        request.uploadUrl.toString(),
        data: await _requestBody(file, request),
        cancelToken: token,
        onSendProgress: (sent, total) => _reportProgress(taskId, sent, total),
        options: Options(
          method: request.method,
          headers: request.headers,
          sendTimeout: request.timeout,
          receiveTimeout: request.timeout,
          contentType: request.multipart ? null : file.mimeType,
        ),
      );
      final current = _tasks[taskId];
      if (current == null || current.state == FileUploadState.cancelled) return;
      final completed = current.copyWith(
        state: FileUploadState.completed,
        sentBytes: current.totalBytes,
        response: _responseSummary(response),
      );
      _setTask(completed);
      _emit('file.uploadCompleted', completed);
    } on DioException catch (error) {
      final current = _tasks[taskId];
      if (current == null) return;
      if (CancelToken.isCancel(error) || token.isCancelled) {
        final cancelled = current.copyWith(state: FileUploadState.cancelled);
        _setTask(cancelled);
        _emit('file.uploadCancelled', cancelled);
      } else {
        final failed = current.copyWith(
          state: FileUploadState.failed,
          error: <String, Object?>{
            'code': 'UPLOAD_FAILED',
            'message': error.message ?? '文件上传失败。',
            if (error.response?.statusCode != null)
              'statusCode': error.response!.statusCode,
          },
        );
        _setTask(failed);
        _emit('file.uploadFailed', failed);
      }
    } catch (error) {
      final current = _tasks[taskId];
      if (current == null) return;
      final failed = current.copyWith(
        state: FileUploadState.failed,
        error: <String, Object?>{'code': 'UPLOAD_FAILED', 'message': '$error'},
      );
      _setTask(failed);
      _emit('file.uploadFailed', failed);
    } finally {
      _cancelTokens.remove(taskId);
      _lastProgressAt.remove(taskId);
    }
  }

  Future<Object> _requestBody(
    SelectedFile file,
    FileUploadRequest request,
  ) async {
    if (!request.multipart) return file.readAsByteStream();
    return FormData.fromMap(<String, Object>{
      ...request.formData,
      request.fieldName: MultipartFile.fromStream(
        file.readAsByteStream,
        file.size,
        filename: file.name,
      ),
    });
  }

  void _reportProgress(String taskId, int sent, int total) {
    final now = DateTime.now();
    final last = _lastProgressAt[taskId];
    final effectiveTotal = total > 0 ? total : _tasks[taskId]?.totalBytes ?? 0;
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 100)) {
      return;
    }
    _lastProgressAt[taskId] = now;
    final current = _tasks[taskId];
    if (current == null || current.state != FileUploadState.uploading) return;
    final uploading = current.copyWith(
      sentBytes: sent,
      totalBytes: effectiveTotal,
    );
    _setTask(uploading);
    _emit('file.uploadProgress', uploading);
  }

  void _validateRequest(FileUploadRequest request) {
    if (!(request.uploadUrl.isScheme('https') ||
        request.uploadUrl.isScheme('http'))) {
      throw const FileUploadException(
        'INVALID_ARGUMENT',
        'uploadUrl 必须使用 http 或 https。',
      );
    }
    if (_allowedHosts.isEmpty) {
      throw const FileUploadException(
        'UPLOAD_DISABLED',
        '当前环境未配置 JS Bridge 允许上传的主机。',
      );
    }
    if (!_allowedHosts.contains(request.uploadUrl.host.toLowerCase())) {
      throw FileUploadException(
        'UPLOAD_HOST_NOT_ALLOWED',
        '上传地址主机未被当前环境允许。',
        details: <String, Object?>{'host': request.uploadUrl.host},
      );
    }
    if (request.method != 'POST' && request.method != 'PUT') {
      throw const FileUploadException(
        'INVALID_ARGUMENT',
        '上传 method 仅支持 POST 或 PUT。',
      );
    }
  }

  void _setTask(FileUploadTask task) => _tasks[task.taskId] = task;

  void _emit(String name, FileUploadTask task) {
    if (!_events.isClosed) _events.add(FileUploadEvent(name: name, task: task));
  }

  Map<String, Object?> _responseSummary(Response<dynamic> response) =>
      <String, Object?>{
        'statusCode': response.statusCode,
        'data': _safeResponseData(response.data),
      };

  Object? _safeResponseData(Object? data) {
    try {
      final encoded = jsonEncode(data);
      if (encoded.length > 16 * 1024) {
        return '${encoded.substring(0, 16 * 1024)}…';
      }
      return jsonDecode(encoded);
    } catch (_) {
      final text = '$data';
      return text.length <= 16 * 1024
          ? text
          : '${text.substring(0, 16 * 1024)}…';
    }
  }

  bool _isTerminal(FileUploadState state) =>
      state == FileUploadState.completed ||
      state == FileUploadState.failed ||
      state == FileUploadState.cancelled;

  @override
  Future<void> dispose() async {
    for (final token in _cancelTokens.values) {
      token.cancel('Upload service disposed');
    }
    _cancelTokens.clear();
    await _events.close();
  }
}

class UnsupportedFileUploadService implements FileUploadService {
  @override
  Stream<FileUploadEvent> get events => const Stream<FileUploadEvent>.empty();

  @override
  Future<bool> cancel(String taskId) async => false;

  @override
  Future<void> dispose() async {}

  @override
  Future<FileUploadTask> start(SelectedFile file, FileUploadRequest request) =>
      Future<FileUploadTask>.error(
        const FileUploadException('NOT_SUPPORTED', '当前宿主未配置文件上传服务。'),
      );

  @override
  FileUploadTask? task(String taskId) => null;
}
