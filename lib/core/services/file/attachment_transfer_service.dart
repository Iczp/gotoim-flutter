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
  String? _activeUserId;

  String _stateKey(String id, {String? userId}) {
    final trimmedUser = userId?.trim() ?? '';
    return trimmedUser.isEmpty ? id : '$trimmedUser::$id';
  }

  AttachmentTransferState stateFor(String id, {String? userId}) {
    final effectiveUser = (userId?.trim().isNotEmpty == true)
        ? userId!.trim()
        : _activeUserId;
    return _states[_stateKey(id, userId: effectiveUser)] ??
        const AttachmentTransferState();
  }

  /// 清空内存传输状态与字节缓存（账号切换或登出时调用，防止跨账号复用内存状态）
  void clearSessionCache() {
    _activeUserId = null;
    if (_states.isEmpty && _bytes.isEmpty && _cancelled.isEmpty) return;
    _states.clear();
    _bytes.clear();
    _cancelled.clear();
    notifyListeners();
  }

  Future<void> registerLocalFile({
    required String id,
    required String localPath,
    int? totalBytes,
    String? userId,
  }) async {
    if (userId?.trim().isNotEmpty == true) {
      _activeUserId = userId!.trim();
    }
    if (localPath.trim().isEmpty) return;
    if (!await _cache.exists(localPath)) return;
    _states[_stateKey(id, userId: userId)] = AttachmentTransferState(
      status: AttachmentTransferStatus.completed,
      receivedBytes: totalBytes ?? 0,
      totalBytes: totalBytes ?? 0,
      localPath: localPath,
    );
    notifyListeners();
  }

  Future<String?> findCachedPath({
    required String id,
    required String fileName,
    String? source,
    String? localFilePath,
    String? userId,
    String? chatTarget,
    DateTime? messageDate,
    String? category,
  }) async {
    if (userId?.trim().isNotEmpty == true) {
      _activeUserId = userId!.trim();
    }
    final sk = _stateKey(id, userId: userId);
    final existing = _states[sk]?.localPath;
    if (existing != null && await _cache.exists(existing)) return existing;
    if (localFilePath != null &&
        localFilePath.trim().isNotEmpty &&
        await _cache.exists(localFilePath)) {
      _states[sk] = AttachmentTransferState(
        status: AttachmentTransferStatus.completed,
        localPath: localFilePath,
      );
      notifyListeners();
      return localFilePath;
    }
    final cacheKey = _cacheKeyFor(id: id, source: source);
    var cached = await _cache.find(
      cacheKey,
      fileName,
      userId: userId,
      chatTarget: chatTarget,
      messageDate: messageDate,
      category: category,
    );
    if (cached == null && cacheKey != id) {
      cached = await _cache.find(
        id,
        fileName,
        userId: userId,
        chatTarget: chatTarget,
        messageDate: messageDate,
        category: category,
      );
    }
    if (cached != null) {
      _states[sk] = AttachmentTransferState(
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
    String? localFilePath,
    String? userId,
    String? chatTarget,
    DateTime? messageDate,
    String? category,
  }) async {
    if (stateFor(id, userId: userId).isDownloading) return;
    final cached = await findCachedPath(
      id: id,
      fileName: fileName,
      source: source,
      localFilePath: localFilePath,
      userId: userId,
      chatTarget: chatTarget,
      messageDate: messageDate,
      category: category,
    );
    if (cached != null) return;
    final sk = _stateKey(id, userId: userId);
    _cancelled.remove(sk);
    final resolved = _resolve(source);
    if (resolved.isEmpty) throw StateError('附件下载地址为空。');
    final cacheKey = _cacheKeyFor(id: id, source: source);
    _states[sk] = const AttachmentTransferState(
      status: AttachmentTransferStatus.downloading,
    );
    notifyListeners();
    try {
      final data = Uint8List.fromList(
        await _client.getBytes(
          resolved,
          cancelTag: _tag(sk),
          onProgress: (received, total) {
            if (_cancelled.contains(sk)) return;
            _states[sk] = AttachmentTransferState(
              status: AttachmentTransferStatus.downloading,
              receivedBytes: received,
              totalBytes: total,
            );
            notifyListeners();
          },
        ),
      );
      if (_cancelled.contains(sk)) return;
      _bytes[sk] = data;
      final localPath = await _cache.write(
        cacheKey,
        fileName,
        data,
        userId: userId,
        chatTarget: chatTarget,
        messageDate: messageDate,
        category: category,
      );
      _states[sk] = AttachmentTransferState(
        status: AttachmentTransferStatus.completed,
        receivedBytes: data.length,
        totalBytes: data.length,
        localPath: localPath,
      );
    } catch (error) {
      final text = error.toString().toLowerCase();
      _states[sk] = AttachmentTransferState(
        status:
            text.contains('cancel')
                ? AttachmentTransferStatus.cancelled
                : AttachmentTransferStatus.failed,
        error: error,
      );
    }
    notifyListeners();
  }

  Future<void> cancel(String id, {String? userId}) async {
    final sk = _stateKey(id, userId: userId);
    _cancelled.add(sk);
    await _client.cancelByTag(_tag(sk));
    if (!stateFor(id, userId: userId).isDownloading) return;
    _states[sk] = const AttachmentTransferState(
      status: AttachmentTransferStatus.cancelled,
    );
    notifyListeners();
  }

  Future<void> open({
    required String id,
    required String source,
    required String fileName,
    String? localFilePath,
    String? userId,
    String? chatTarget,
    DateTime? messageDate,
    String? category,
  }) async {
    var state = stateFor(id, userId: userId);
    if (!state.isReady || state.localPath == null) {
      await download(
        id: id,
        source: source,
        fileName: fileName,
        localFilePath: localFilePath,
        userId: userId,
        chatTarget: chatTarget,
        messageDate: messageDate,
        category: category,
      );
      state = stateFor(id, userId: userId);
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
    String? localFilePath,
    String? userId,
    String? chatTarget,
    DateTime? messageDate,
    String? category,
    String? mimeType,
  }) async {
    final sk = _stateKey(id, userId: userId);
    if (!_bytes.containsKey(sk)) {
      final cachedPath = await findCachedPath(
        id: id,
        fileName: fileName,
        source: source,
        localFilePath: localFilePath,
        userId: userId,
        chatTarget: chatTarget,
        messageDate: messageDate,
        category: category,
      );
      if (cachedPath != null) {
        final localBytes = await _cache.readBytes(cachedPath);
        if (localBytes != null) {
          _bytes[sk] = localBytes;
        }
      }
    }
    if (!_bytes.containsKey(sk)) {
      await download(
        id: id,
        source: source,
        fileName: fileName,
        localFilePath: localFilePath,
        userId: userId,
        chatTarget: chatTarget,
        messageDate: messageDate,
        category: category,
      );
    }
    final data = _bytes[sk];
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

  String _cacheKeyFor({required String id, String? source}) =>
      normalizeAttachmentCacheKey(
        source: source,
        fallbackKey: id,
        serverOrigin: _environment.apiBaseUrl,
      );

  Object _tag(String id) => 'attachment-$id';
}
