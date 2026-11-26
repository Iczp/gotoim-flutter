import 'package:flutter/foundation.dart';

import '../../config/app_environment.dart';
import '../../network/api_client.dart';
import '../../utils/api_url_resolver.dart';
import 'attachment_cache.dart';
import 'file_picker_service.dart';

@immutable
class AttachmentAccessContext {
  const AttachmentAccessContext({
    this.sessionUnitId,
    this.messageId,
    this.rootMessageId,
  });

  final String? sessionUnitId;
  final int? messageId;
  final int? rootMessageId;
}

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
  final Map<String, DateTime> _authorizedVerdicts = {};
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
    if (_states.isEmpty &&
        _bytes.isEmpty &&
        _cancelled.isEmpty &&
        _authorizedVerdicts.isEmpty) {
      return;
    }
    _states.clear();
    _bytes.clear();
    _cancelled.clear();
    _authorizedVerdicts.clear();
    notifyListeners();
  }

  /// 消息撤回或删除时使对应在线授权结果与进行中的传输失效
  void invalidateMessageAccess({
    int? messageId,
    String? localId,
    String? userId,
  }) {
    if (messageId != null && messageId > 0) {
      final target = '$messageId';
      _authorizedVerdicts.removeWhere((key, _) {
        final parts = key.split('|');
        return parts.length >= 6 && (parts[4] == target || parts[5] == target);
      });
    }
    if (localId != null && localId.trim().isNotEmpty) {
      final effectiveUser =
          (userId?.trim().isNotEmpty == true) ? userId!.trim() : _activeUserId;
      final sk = _stateKey(localId.trim(), userId: effectiveUser);
      _states.remove(sk);
      _bytes.remove(sk);
      _cancelled.add(sk);
      _client.cancelByTag(_tag(sk));
      notifyListeners();
    }
  }

  static int _defaultPortForScheme(String scheme) =>
      scheme.toLowerCase() == 'https' ? 443 : 80;

  static bool _isSameOriginUri(Uri a, Uri b) {
    if (!a.hasScheme || !b.hasScheme) return false;
    final portA = a.hasPort ? a.port : _defaultPortForScheme(a.scheme);
    final portB = b.hasPort ? b.port : _defaultPortForScheme(b.scheme);
    return a.scheme.toLowerCase() == b.scheme.toLowerCase() &&
        a.host.toLowerCase() == b.host.toLowerCase() &&
        portA == portB;
  }

  String _effectiveSessionUnitId(
    String resolvedUrl,
    AttachmentAccessContext? accessContext,
  ) {
    final explicit = accessContext?.sessionUnitId?.trim() ?? '';
    if (explicit.isNotEmpty) return explicit;
    return Uri.tryParse(resolvedUrl)?.queryParameters['su']?.trim() ?? '';
  }

  /// 在线校验私有聊天附件访问权限（通过 POST /api/chat/file/sign）并短时缓存结论
  Future<bool> authorizePrivateAttachment(
    String source, {
    AttachmentAccessContext? accessContext,
    String? userId,
  }) async {
    final resolved = _resolve(source);
    if (resolved.isEmpty) return false;
    final blobId = extractAttachmentBlobId(resolved);
    if (blobId == null) return true;

    final targetUri = Uri.tryParse(resolved);
    final apiUri = Uri.tryParse(_environment.apiBaseUrl.trim());
    if (targetUri != null &&
        targetUri.hasScheme &&
        apiUri != null &&
        apiUri.hasScheme &&
        !_isSameOriginUri(targetUri, apiUri)) {
      return true;
    }

    final su = _effectiveSessionUnitId(resolved, accessContext);
    if (su.isEmpty) {
      // 缺少消息上下文的旧链接不得直接命中私有磁盘缓存，必须走在线请求校验
      return false;
    }
    final msg =
        accessContext?.messageId ??
        int.tryParse(targetUri?.queryParameters['msg'] ?? '');
    final rootMsg =
        accessContext?.rootMessageId ??
        int.tryParse(targetUri?.queryParameters['rootMsg'] ?? '');

    final effectiveUser =
        (userId?.trim().isNotEmpty == true)
            ? userId!.trim()
            : (_activeUserId ?? 'anon');
    final origin =
        targetUri != null && targetUri.hasScheme
            ? '${targetUri.scheme.toLowerCase()}://${targetUri.host.toLowerCase()}:${targetUri.hasPort ? targetUri.port : _defaultPortForScheme(targetUri.scheme)}'
            : 'default';
    final verdictKey =
        '$effectiveUser|$origin|$blobId|$su|${msg ?? ''}|${rootMsg ?? ''}';

    final cachedUntil = _authorizedVerdicts[verdictKey];
    if (cachedUntil != null) {
      if (cachedUntil.isAfter(DateTime.now())) {
        return true;
      }
      _authorizedVerdicts.remove(verdictKey);
    }

    try {
      await _client.post<dynamic>(
        '/api/chat/file/sign',
        query: <String, Object?>{
          'blobId': blobId,
          'sessionUnitId': su,
          if (msg != null && msg > 0) 'messageId': msg,
          if (rootMsg != null && rootMsg > 0) 'rootMessageId': rootMsg,
        },
      );
      _authorizedVerdicts[verdictKey] = DateTime.now().add(
        const Duration(seconds: 60),
      );
      return true;
    } catch (_) {
      return false;
    }
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
    AttachmentAccessContext? accessContext,
    bool verifyOnline = false,
  }) async {
    if (userId?.trim().isNotEmpty == true) {
      _activeUserId = userId!.trim();
    }
    if ((accessContext != null || verifyOnline) &&
        source != null &&
        source.trim().isNotEmpty) {
      final allowed = await authorizePrivateAttachment(
        source,
        accessContext: accessContext,
        userId: userId,
      );
      if (!allowed) return null;
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
    AttachmentAccessContext? accessContext,
    bool verifyOnline = false,
  }) async {
    if (stateFor(id, userId: userId).isDownloading) return;
    final contextualSource = resolveAttachmentUrl(
      source,
      _environment.apiBaseUrl,
      sessionUnitId: accessContext?.sessionUnitId,
      messageId: accessContext?.messageId,
      rootMessageId: accessContext?.rootMessageId,
    );
    final effectiveSource =
        contextualSource.isNotEmpty ? contextualSource : source;
    final cached = await findCachedPath(
      id: id,
      fileName: fileName,
      source: effectiveSource,
      localFilePath: localFilePath,
      userId: userId,
      chatTarget: chatTarget,
      messageDate: messageDate,
      category: category,
      accessContext: accessContext,
      verifyOnline: verifyOnline,
    );
    if (cached != null) return;
    final sk = _stateKey(id, userId: userId);
    _cancelled.remove(sk);
    final resolved = _resolve(effectiveSource);
    if (resolved.isEmpty) throw StateError('附件下载地址为空。');
    if ((accessContext != null || verifyOnline) &&
        _effectiveSessionUnitId(resolved, accessContext).isNotEmpty) {
      final allowed = await authorizePrivateAttachment(
        resolved,
        accessContext: accessContext,
        userId: userId,
      );
      if (!allowed) {
        _states[sk] = AttachmentTransferState(
          status: AttachmentTransferStatus.failed,
          error: StateError('无权访问该私有附件或消息已撤回/删除'),
        );
        notifyListeners();
        return;
      }
    }
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
    final effectiveUser =
        (userId?.trim().isNotEmpty == true) ? userId!.trim() : _activeUserId;
    final sk = _stateKey(id, userId: effectiveUser);
    _cancelled.add(sk);
    await _client.cancelByTag(_tag(sk));
    if (!stateFor(id, userId: effectiveUser).isDownloading) return;
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
    AttachmentAccessContext? accessContext,
    bool verifyOnline = false,
  }) async {
    var state = stateFor(id, userId: userId);
    final shouldVerify = accessContext != null || verifyOnline;
    if (!state.isReady || state.localPath == null || shouldVerify) {
      await download(
        id: id,
        source: source,
        fileName: fileName,
        localFilePath: localFilePath,
        userId: userId,
        chatTarget: chatTarget,
        messageDate: messageDate,
        category: category,
        accessContext: accessContext,
        verifyOnline: verifyOnline,
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
    AttachmentAccessContext? accessContext,
    bool verifyOnline = false,
  }) async {
    final sk = _stateKey(id, userId: userId);
    final shouldVerify = accessContext != null || verifyOnline;
    if (shouldVerify && source.trim().isNotEmpty) {
      _bytes.remove(sk);
    }
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
        accessContext: accessContext,
        verifyOnline: verifyOnline,
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
        accessContext: accessContext,
        verifyOnline: verifyOnline,
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
