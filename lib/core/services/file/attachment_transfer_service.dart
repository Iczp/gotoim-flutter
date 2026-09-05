import 'package:flutter/foundation.dart';

import '../../config/app_environment.dart';
import '../../network/api_client.dart';
import 'attachment_cache.dart';
import 'file_picker_service.dart';

enum AttachmentTransferStatus {
  idle,
  downloading,
  completed,
  cancelled,
  failed,
}

@immutable
class AttachmentTransferState {
  const AttachmentTransferState({
    this.status = AttachmentTransferStatus.idle,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.localPath,
    this.error,
  });

  final AttachmentTransferStatus status;
  final int receivedBytes;
  final int totalBytes;
  final String? localPath;
  final Object? error;

  double? get progress => totalBytes > 0 ? receivedBytes / totalBytes : null;
  bool get isDownloading => status == AttachmentTransferStatus.downloading;
  bool get isReady => status == AttachmentTransferStatus.completed;
}

/// Coordinates attachment download, cache, opening and "save as" actions.
/// It is deliberately UI-agnostic and uses the project's authenticated client.
class AttachmentTransferService extends ChangeNotifier {
  AttachmentTransferService({
    required ApiClient client,
    required AppEnvironment environment,
    required FilePickerService filePickerService,
    AttachmentCache? cache,
  }) : _client = client,
       _environment = environment,
       _filePickerService = filePickerService,
       _cache = cache ?? createAttachmentCache();

  final ApiClient _client;
  final AppEnvironment _environment;
  final FilePickerService _filePickerService;
  final AttachmentCache _cache;
  final Map<String, AttachmentTransferState> _states = {};
  final Map<String, Uint8List> _bytes = {};
  final Set<String> _cancelled = <String>{};

  AttachmentTransferState stateFor(String id) =>
      _states[id] ?? const AttachmentTransferState();

  Future<String?> findCachedPath({
    required String id,
    required String fileName,
    String? userId,
    String? chatTarget,
    DateTime? messageDate,
    String? category,
  }) async {
    final existing = _states[id]?.localPath;
    if (existing != null) return existing;
    final cached = await _cache.find(
      id,
      fileName,
      userId: userId,
      chatTarget: chatTarget,
      messageDate: messageDate,
      category: category,
    );
    if (cached != null) {
      _states[id] = AttachmentTransferState(
        status: AttachmentTransferStatus.completed,
        localPath: cached,
      );
      notifyListeners();
      return cached;
    }
    return null;
  }

  Future<void> download({
    required String id,
    required String source,
    required String fileName,
    String? userId,
    String? chatTarget,
    DateTime? messageDate,
    String? category,
  }) async {
    if (stateFor(id).isDownloading) return;
    final cached = await findCachedPath(
      id: id,
      fileName: fileName,
      userId: userId,
      chatTarget: chatTarget,
      messageDate: messageDate,
      category: category,
    );
    if (cached != null) return;
    _cancelled.remove(id);
    final resolved = _resolve(source);
    if (resolved.isEmpty) throw StateError('附件下载地址为空。');
    _states[id] = const AttachmentTransferState(
      status: AttachmentTransferStatus.downloading,
    );
    notifyListeners();
    try {
      final data = Uint8List.fromList(
        await _client.getBytes(
          resolved,
          cancelTag: _tag(id),
          onProgress: (received, total) {
            if (_cancelled.contains(id)) return;
            _states[id] = AttachmentTransferState(
              status: AttachmentTransferStatus.downloading,
              receivedBytes: received,
              totalBytes: total,
            );
            notifyListeners();
          },
        ),
      );
      if (_cancelled.contains(id)) return;
      _bytes[id] = data;
      final localPath = await _cache.write(
        id,
        fileName,
        data,
        userId: userId,
        chatTarget: chatTarget,
        messageDate: messageDate,
        category: category,
      );
      _states[id] = AttachmentTransferState(
        status: AttachmentTransferStatus.completed,
        receivedBytes: data.length,
        totalBytes: data.length,
        localPath: localPath,
      );
    } catch (error) {
      final text = error.toString().toLowerCase();
      _states[id] = AttachmentTransferState(
        status:
            text.contains('cancel')
                ? AttachmentTransferStatus.cancelled
                : AttachmentTransferStatus.failed,
        error: error,
      );
    }
    notifyListeners();
  }

  Future<void> cancel(String id) async {
    _cancelled.add(id);
    await _client.cancelByTag(_tag(id));
    if (!stateFor(id).isDownloading) return;
    _states[id] = const AttachmentTransferState(
      status: AttachmentTransferStatus.cancelled,
    );
    notifyListeners();
  }

  Future<void> open({
    required String id,
    required String source,
    required String fileName,
    String? userId,
    String? chatTarget,
    DateTime? messageDate,
    String? category,
  }) async {
    var state = stateFor(id);
    if (!state.isReady) {
      await download(
        id: id,
        source: source,
        fileName: fileName,
        userId: userId,
        chatTarget: chatTarget,
        messageDate: messageDate,
        category: category,
      );
      state = stateFor(id);
    }
    final path = state.localPath;
    if (path == null) {
      throw UnsupportedError('当前平台不支持直接打开附件，请使用“另存为”。');
    }
    await _cache.open(path);
  }

  Future<SavedFile?> saveAs({
    required String id,
    required String source,
    required String fileName,
    String? userId,
    String? chatTarget,
    DateTime? messageDate,
    String? category,
    String? mimeType,
  }) async {
    if (!_bytes.containsKey(id)) {
      await download(
        id: id,
        source: source,
        fileName: fileName,
        userId: userId,
        chatTarget: chatTarget,
        messageDate: messageDate,
        category: category,
      );
    }
    final data = _bytes[id];
    if (data == null) return null;
    return _filePickerService.saveFile(
      FileSaveRequest(
        fileName: fileName,
        bytes: data,
        mimeType: mimeType ?? 'application/octet-stream',
        dialogTitle: '另存为',
      ),
    );
  }

  String _resolve(String source) {
    final value = source.trim();
    if (value.isEmpty) return '';
    final uri = Uri.tryParse(value);
    return uri?.hasScheme == true
        ? value
        : Uri.parse(_environment.apiBaseUrl).resolve(value).toString();
  }

  Object _tag(String id) => 'attachment-$id';
}
