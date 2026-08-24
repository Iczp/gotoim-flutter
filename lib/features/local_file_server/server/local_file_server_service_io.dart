import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/notifications/local_notification_contract.dart';
import '../models/connected_terminal.dart';
import '../models/local_file_server_state.dart';

/// Native-only LAN file server. All caller-provided paths are virtual paths
/// validated segment-by-segment before they are resolved beneath [_shareRoot].
class LocalFileServerService extends ChangeNotifier {
  static const _chunkSize = 4 * 1024 * 1024;
  static const _notificationId = 4783201;
  static const _stopActionId = 'local_file_server.stop';
  static const _disconnectActionId = 'local_file_server.disconnect_all';
  LocalFileServerService({
    required LocalNotificationService notifications,
    required String shareName,
  }) : _notifications = notifications,
       _shareName = shareName {
    _notificationSubscription = _notifications.tapEvents.listen(
      _handleNotificationAction,
    );
  }

  final LocalNotificationService _notifications;
  final String _shareName;
  late final StreamSubscription<LocalNotificationTapEvent>
  _notificationSubscription;
  final Random _random = Random.secure();
  final Map<String, _TerminalSocket> _sockets = {};
  final Map<String, ConnectedTerminal> _knownTerminals = {};
  final Map<String, _Upload> _uploads = {};
  final Map<String, String?> _sessions = {};
  final Map<String, List<TerminalActivity>> _activities = {};
  final Map<String, DateTime> _qrTokens = {};
  LocalFileServerState _state = const LocalFileServerState.stopped();
  HttpServer? _server;
  Directory? _shareRoot;
  Timer? _terminalSweeper;

  LocalFileServerState get state => _state;
  int get uploadChunkSize => _chunkSize;
  List<TerminalActivity> activitiesFor(String terminalId) =>
      List.unmodifiable(_activities[terminalId] ?? const []);
  ConnectedTerminal? terminalFor(String terminalId) =>
      _sockets[terminalId]?.terminal ?? _knownTerminals[terminalId];

  Future<void> start() async {
    if (_server != null) {
      return;
    }
    _setState(
      _state.copyWith(status: LocalFileServerStatus.starting, error: null),
    );
    try {
      _shareRoot = Directory(
        '${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}LocalShare',
      );
      await _shareRoot!.create(recursive: true);
      await _createDefaultFolders();
      HttpServer? server;
      for (var port = 47832; port <= 47862; port++) {
        try {
          server = await HttpServer.bind(
            InternetAddress.anyIPv4,
            port,
            shared: true,
          );
          break;
        } on SocketException {
          // Try the next port in the reserved local-sharing range.
        }
      }
      if (server == null) throw StateError('47832–47862 均不可用。');
      _server = server;
      unawaited(server.forEach(_handle));
      _terminalSweeper = Timer.periodic(
        const Duration(seconds: 15),
        (_) => _expireInactiveTerminals(),
      );
      final address = 'http://${await _lanAddress()}:${server.port}';
      final qrToken = _token();
      _qrTokens[qrToken] = DateTime.now().add(const Duration(minutes: 5));
      _setState(
        LocalFileServerState(
          status: LocalFileServerStatus.running,
          address: address,
          qrLoginUrl: '$address/?token=$qrToken',
          verificationCode: _verificationCode(),
          terminals: const [],
        ),
      );
      await _refreshShareNotification();
    } catch (error) {
      _setState(
        LocalFileServerState(
          status: LocalFileServerStatus.failed,
          error: '$error',
        ),
      );
      final server = _server;
      _server = null;
      await server?.close(force: true);
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    for (final item in _sockets.values) {
      await item.socket.close(WebSocketStatus.goingAway, 'Server stopped');
    }
    _sockets.clear();
    _knownTerminals.clear();
    _sessions.clear();
    _activities.clear();
    _qrTokens.clear();
    _uploads.clear();
    _terminalSweeper?.cancel();
    _terminalSweeper = null;
    await server?.close(force: true);
    await _notifications.cancel(_notificationId);
    _setState(const LocalFileServerState.stopped());
  }

  Future<void> disconnectTerminal(String terminalId) async {
    final terminal = _sockets.remove(terminalId);
    if (terminal != null) {
      _knownTerminals[terminalId] = terminal.terminal.copyWith(
        lastActiveAt: DateTime.now(),
        status: TerminalStatus.offline,
      );
    }
    _recordActivity(terminalId, 'disconnect', '已由 App 断开连接');
    await terminal?.socket.close(
      WebSocketStatus.policyViolation,
      'Disconnected by owner',
    );
    _publishTerminals();
  }

  Future<void> disconnectAllTerminals() async {
    final terminalIds = _sockets.keys.toList();
    for (final terminalId in terminalIds) {
      await disconnectTerminal(terminalId);
    }
  }

  Future<void> close() async {
    await _notificationSubscription.cancel();
    await stop();
  }

  Future<void> _handleNotificationAction(
    LocalNotificationTapEvent event,
  ) async {
    if (event.actionId == _stopActionId) {
      await stop();
    } else if (event.actionId == _disconnectActionId) {
      await disconnectAllTerminals();
    }
  }

  Future<void> _refreshShareNotification() async {
    if (_state.status != LocalFileServerStatus.running) {
      return;
    }
    final permission = await _notifications.requestPermission();
    if (permission.status == LocalNotificationPermissionStatus.denied ||
        permission.status == LocalNotificationPermissionStatus.unsupported) {
      return;
    }
    final connected = _sockets.length;
    await _notifications.show(
      LocalNotificationRequest(
        id: _notificationId,
        channelId: 'local_file_sharing',
        channelName: '局域网文件共享',
        title: '局域网文件共享已开启',
        body: connected == 0 ? '暂无设备连接' : '已有 $connected 台设备连接',
        payload: 'local-file-server',
        ongoing: true,
        actions: const [
          LocalNotificationAction(id: _disconnectActionId, title: '断开全部'),
          LocalNotificationAction(id: _stopActionId, title: '关闭共享'),
        ],
      ),
    );
  }

  void _expireInactiveTerminals() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 45));
    final expired =
        _sockets.entries
            .where(
              (entry) => entry.value.terminal.lastActiveAt.isBefore(cutoff),
            )
            .toList();
    for (final entry in expired) {
      _sockets.remove(entry.key);
      unawaited(
        entry.value.socket.close(
          WebSocketStatus.goingAway,
          'Heartbeat timeout',
        ),
      );
    }
    if (expired.isNotEmpty) {
      _publishTerminals();
    }
  }

  Future<void> _createDefaultFolders() async {
    for (final name in ['图片', '视频', '文档', '下载', '聊天文件']) {
      await Directory(
        '${_shareRoot!.path}${Platform.pathSeparator}$name',
      ).create();
    }
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (path == '/ws') {
        await _webSocket(request);
        return;
      }
      if (path == '/api/auth/login' && request.method == 'POST') {
        await _login(request);
        return;
      }
      if (path == '/api/share-info' && request.method == 'GET') {
        _json(request.response, HttpStatus.ok, {
          'title': '$_shareName 的${_hostDeviceLabel()}文件',
        });
        return;
      }
      if (path == '/' || path.startsWith('/assets/')) {
        await _asset(request);
        return;
      }
      if (!await _authorized(request)) {
        _json(request.response, HttpStatus.unauthorized, {
          'error': 'AUTH_REQUIRED',
        });
        return;
      }
      final terminalId = _terminalId(request);
      if (path == '/api/files' && request.method == 'GET') {
        await _listFiles(request, terminalId: terminalId);
        return;
      }
      if (path == '/api/files/info' && request.method == 'GET') {
        await _fileInfo(request, terminalId: terminalId);
        return;
      }
      if (path == '/api/files/content' && request.method == 'GET') {
        await _content(request, terminalId: terminalId);
        return;
      }
      if (path == '/api/files/mkdir' && request.method == 'POST') {
        await _mkdir(request, terminalId: terminalId);
        return;
      }
      if (path == '/api/files/rename' && request.method == 'PUT') {
        await _rename(request, terminalId: terminalId);
        return;
      }
      if (path == '/api/files/move' && request.method == 'PUT') {
        await _move(request, terminalId: terminalId);
        return;
      }
      if (path == '/api/files' && request.method == 'DELETE') {
        await _delete(request, terminalId: terminalId);
        return;
      }
      if (path == '/api/uploads' && request.method == 'POST') {
        await _createUpload(request, terminalId: terminalId);
        return;
      }
      final match = RegExp(
        r'^/api/uploads/([^/]+)(?:/chunks/(\d+))?$',
      ).firstMatch(path);
      if (match != null) {
        await _uploadRoute(request, match.group(1)!, match.group(2));
        return;
      }
      _json(request.response, HttpStatus.notFound, {'error': 'NOT_FOUND'});
    } catch (error) {
      _json(request.response, HttpStatus.badRequest, {
        'error': 'BAD_REQUEST',
        'message': '$error',
      });
    }
  }

  Future<bool> _authorized(HttpRequest request) async {
    return request.cookies.any(
      (cookie) =>
          cookie.name == 'lf_session' && _sessions.containsKey(cookie.value),
    );
  }

  Future<void> _login(HttpRequest request) async {
    final body = await _body(request);
    final qrToken = body['qrToken'] as String?;
    final expiresAt = qrToken == null ? null : _qrTokens.remove(qrToken);
    final qrValid = expiresAt != null && expiresAt.isAfter(DateTime.now());
    if (!qrValid && body['code'] != _state.verificationCode) {
      _json(request.response, HttpStatus.unauthorized, {
        'error': 'INVALID_CODE',
      });
      return;
    }
    final token = _token();
    _sessions[token] = null;
    request.response.cookies.add(
      Cookie('lf_session', token)
        ..httpOnly = true
        ..sameSite = SameSite.lax
        ..path = '/',
    );
    _json(request.response, HttpStatus.ok, {'ok': true});
  }

  Future<void> _asset(HttpRequest request) async {
    final asset =
        request.uri.path == '/' ? 'index.html' : request.uri.path.substring(1);
    if (asset.contains('..')) {
      throw FormatException('Invalid asset path');
    }
    try {
      final data = await rootBundle.load('assets/file_web/$asset');
      request.response.headers.contentType = _contentType(asset);
      request.response.add(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } catch (_) {
      final index = await rootBundle.load('assets/file_web/index.html');
      request.response.headers.contentType = ContentType.html;
      request.response.add(
        index.buffer.asUint8List(index.offsetInBytes, index.lengthInBytes),
      );
    }
    await request.response.close();
  }

  Future<void> _listFiles(HttpRequest request, {String? terminalId}) async {
    final relative = request.uri.queryParameters['path'] ?? '/';
    final dir = _resolve(relative);
    if (!await dir.exists()) {
      throw FileSystemException('目录不存在');
    }
    final values = <Map<String, Object?>>[];
    await for (final entity in dir.list(followLinks: false)) {
      final stat = await entity.stat();
      values.add({
        'name': _name(entity.path),
        'path': _virtual(entity.path),
        'isDirectory': entity is Directory,
        'size': stat.size,
        'modifiedAt': stat.modified.toIso8601String(),
      });
    }
    values.sort((a, b) {
      final aDirectory = a['isDirectory'] as bool;
      final bDirectory = b['isDirectory'] as bool;
      if (aDirectory != bDirectory) return aDirectory ? -1 : 1;
      return (a['name'] as String).compareTo(b['name'] as String);
    });
    _json(request.response, HttpStatus.ok, {'path': relative, 'items': values});
  }

  Future<void> _fileInfo(HttpRequest request, {String? terminalId}) async {
    final file = File(_resolvePath(request.uri.queryParameters['path']));
    final stat = await file.stat();
    _json(request.response, HttpStatus.ok, {
      'path': _virtual(file.path),
      'size': stat.size,
      'modifiedAt': stat.modified.toIso8601String(),
    });
  }

  Future<void> _content(HttpRequest request, {String? terminalId}) async {
    final file = File(_resolvePath(request.uri.queryParameters['path']));
    if (!await file.exists()) {
      _json(request.response, HttpStatus.notFound, {'error': 'NOT_FOUND'});
      return;
    }
    _recordActivity(terminalId, 'download', '请求下载 / ${_name(file.path)}');
    final total = await file.length();
    var start = 0;
    var end = total - 1;
    final range = request.headers.value(HttpHeaders.rangeHeader);
    if (range != null) {
      final match = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(range);
      if (match == null) {
        _rangeError(request.response, total);
        return;
      }
      start = match.group(1)!.isEmpty ? 0 : int.parse(match.group(1)!);
      end = match.group(2)!.isEmpty ? end : int.parse(match.group(2)!);
      if (start > end || start >= total) {
        _rangeError(request.response, total);
        return;
      }
      end = min(end, total - 1);
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$total',
      );
    }
    request.response.headers
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..contentLength = end - start + 1
      ..contentType = _contentType(file.path)
      ..set('content-disposition', 'inline; filename="${_name(file.path)}"');
    await request.response.addStream(file.openRead(start, end + 1));
    await request.response.close();
  }

  Future<void> _mkdir(HttpRequest request, {String? terminalId}) async {
    final body = await _body(request);
    final parent = _resolve(body['parentPath'] as String? ?? '/');
    final name = _segment(body['name'] as String?);
    await Directory('${parent.path}${Platform.pathSeparator}$name').create();
    _recordActivity(terminalId, 'mkdir', '新建文件夹 $name');
    _broadcast({'type': 'files.changed'});
    _json(request.response, HttpStatus.created, {
      'path': _virtual('${parent.path}${Platform.pathSeparator}$name'),
    });
  }

  Future<void> _rename(HttpRequest request, {String? terminalId}) async {
    final body = await _body(request);
    final source = _entity(body['path'] as String?);
    final target =
        '${_parent(source.path)}${Platform.pathSeparator}${_segment(body['name'] as String?)}';
    await source.rename(target);
    _recordActivity(
      terminalId,
      'rename',
      '重命名 ${_name(source.path)} 为 ${_name(target)}',
    );
    _broadcast({'type': 'files.changed'});
    _json(request.response, HttpStatus.ok, {'path': _virtual(target)});
  }

  Future<void> _move(HttpRequest request, {String? terminalId}) async {
    final body = await _body(request);
    final source = _entity(body['path'] as String?);
    final targetDir = _resolve(body['targetPath'] as String? ?? '/');
    final target =
        '${targetDir.path}${Platform.pathSeparator}${_name(source.path)}';
    await source.rename(target);
    _recordActivity(
      terminalId,
      'move',
      '移动 ${_name(source.path)} 至 ${_virtual(targetDir.path)}',
    );
    _broadcast({'type': 'files.changed'});
    _json(request.response, HttpStatus.ok, {'path': _virtual(target)});
  }

  Future<void> _delete(HttpRequest request, {String? terminalId}) async {
    final path = request.uri.queryParameters['path'];
    final entity = _entity(path);
    if (_virtual(entity.path) == '/') {
      throw FormatException('不能删除共享根目录');
    }
    await entity.delete(recursive: entity is Directory);
    _recordActivity(terminalId, 'delete', '删除 ${_virtual(entity.path)}');
    _broadcast({'type': 'files.changed'});
    _json(request.response, HttpStatus.ok, {'ok': true});
  }

  Future<void> _createUpload(HttpRequest request, {String? terminalId}) async {
    final body = await _body(request);
    final id = _token();
    final name = _segment(body['name'] as String?);
    final parentPath = body['parentPath'] as String? ?? '/';
    final total =
        body['size'] is num
            ? (body['size'] as num).toInt()
            : throw FormatException('size is required');
    final chunks =
        body['chunks'] is num
            ? (body['chunks'] as num).toInt()
            : (total / _chunkSize).ceil();
    final temp = Directory(
      '${_shareRoot!.path}${Platform.pathSeparator}.uploads${Platform.pathSeparator}$id',
    );
    await temp.create(recursive: true);
    _uploads[id] = _Upload(
      id: id,
      name: name,
      parentPath: parentPath,
      total: total,
      chunks: chunks,
      temp: temp,
      terminalId: terminalId,
    );
    _json(request.response, HttpStatus.created, {
      'id': id,
      'chunkSize': _chunkSize,
      'uploadedChunks': const [],
    });
  }

  Future<void> _uploadRoute(
    HttpRequest request,
    String id,
    String? chunk,
  ) async {
    final upload = _uploads[id];
    if (upload == null) {
      _json(request.response, HttpStatus.notFound, {
        'error': 'UPLOAD_NOT_FOUND',
      });
      return;
    }
    if (request.method == 'GET') {
      _json(request.response, HttpStatus.ok, upload.json());
      return;
    }
    if (request.method == 'DELETE') {
      _uploads.remove(id);
      await upload.temp.delete(recursive: true);
      return _json(request.response, HttpStatus.ok, {'ok': true});
    }
    if (request.method == 'PUT' && chunk != null) {
      final index = int.parse(chunk);
      if (index < 0 || index >= upload.chunks) {
        throw RangeError.index(index, upload.chunks);
      }
      final sink =
          File(
            '${upload.temp.path}${Platform.pathSeparator}$index.part',
          ).openWrite();
      await request.forEach(sink.add);
      await sink.close();
      upload.received.add(index);
      _broadcast({
        'type': 'transfer.progress',
        'uploadId': id,
        'fileName': upload.name,
        'received': upload.received.length * _chunkSize,
        'total': upload.total,
      });
      return _json(request.response, HttpStatus.ok, {
        'ok': true,
        'uploadedChunks': upload.received.toList(),
      });
    }
    if (request.method == 'POST' && chunk == null) {
      await _completeUpload(request, upload);
      return;
    }
    _json(request.response, HttpStatus.methodNotAllowed, {
      'error': 'METHOD_NOT_ALLOWED',
    });
  }

  Future<void> _completeUpload(HttpRequest request, _Upload upload) async {
    if (upload.received.length != upload.chunks) {
      throw StateError('仍缺少上传分片');
    }
    final parent = _resolve(upload.parentPath);
    final destination = File(
      '${parent.path}${Platform.pathSeparator}${upload.name}',
    );
    if (await destination.exists()) {
      throw FileSystemException('同名文件已存在');
    }
    final sink = destination.openWrite();
    for (var i = 0; i < upload.chunks; i++) {
      await sink.addStream(
        File('${upload.temp.path}${Platform.pathSeparator}$i.part').openRead(),
      );
    }
    await sink.close();
    _uploads.remove(upload.id);
    await upload.temp.delete(recursive: true);
    _recordActivity(upload.terminalId, 'upload', '上传完成 ${upload.name}');
    _broadcast({'type': 'files.changed'});
    _json(request.response, HttpStatus.created, {
      'path': _virtual(destination.path),
    });
  }

  Future<void> _webSocket(HttpRequest request) async {
    if (!await _authorized(request)) {
      _json(request.response, HttpStatus.unauthorized, {
        'error': 'AUTH_REQUIRED',
      });
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    String? id;
    socket.listen(
      (data) {
        final message = jsonDecode(data as String) as Map<String, dynamic>;
        if (message['type'] == 'hello') {
          id = message['terminalId'] as String? ?? _token();
          final terminal = ConnectedTerminal(
            id: id!,
            name: message['name'] as String? ?? 'Browser',
            platform: message['platform'] as String? ?? 'Unknown',
            ip: request.connectionInfo?.remoteAddress.address ?? '',
            connectedAt: DateTime.now(),
            lastActiveAt: DateTime.now(),
            status: TerminalStatus.idle,
          );
          _sockets[id!] = _TerminalSocket(socket, terminal);
          _knownTerminals[id!] = terminal;
          final sessionToken = _sessionToken(request);
          if (sessionToken != null) {
            _sessions[sessionToken] = id;
          }
          _recordActivity(id, 'connect', '已连接到文件共享服务');
          _publishTerminals();
        } else if (id != null) {
          final current = _sockets[id!];
          if (current != null) {
            final received = message['received'];
            final total = message['total'];
            _sockets[id!] = _TerminalSocket(
              socket,
              current.terminal.copyWith(
                lastActiveAt: DateTime.now(),
                status: _status(message['type'] as String?),
                transferLabel: message['fileName'] as String?,
                receivedBytes: received is num ? received.toInt() : null,
                totalBytes: total is num ? total.toInt() : null,
              ),
            );
            _knownTerminals[id!] = _sockets[id!]!.terminal;
          }
          _publishTerminals();
        }
      },
      onDone: () {
        if (id != null) {
          final terminal = _sockets.remove(id);
          if (terminal != null) {
            _knownTerminals[id!] = terminal.terminal.copyWith(
              lastActiveAt: DateTime.now(),
              status: TerminalStatus.offline,
            );
          }
          _recordActivity(id, 'disconnect', '浏览器已断开连接');
        }
        _publishTerminals();
      },
    );
  }

  TerminalStatus _status(String? type) {
    switch (type) {
      case 'transfer.progress':
        return TerminalStatus.uploading;
      case 'transfer.complete':
      default:
        return TerminalStatus.idle;
    }
  }

  void _broadcast(Map<String, Object?> data) {
    final encoded = jsonEncode(data);
    for (final item in _sockets.values) {
      item.socket.add(encoded);
    }
  }

  void _publishTerminals() {
    _setState(
      _state.copyWith(
        terminals: _sockets.values.map((item) => item.terminal).toList(),
      ),
    );
    unawaited(_refreshShareNotification());
  }

  String? _sessionToken(HttpRequest request) {
    for (final cookie in request.cookies) {
      if (cookie.name == 'lf_session' && _sessions.containsKey(cookie.value)) {
        return cookie.value;
      }
    }
    return null;
  }

  String? _terminalId(HttpRequest request) {
    final sessionToken = _sessionToken(request);
    return sessionToken == null ? null : _sessions[sessionToken];
  }

  void _recordActivity(String? terminalId, String action, String description) {
    if (terminalId == null) {
      return;
    }
    final entries = _activities.putIfAbsent(
      terminalId,
      () => <TerminalActivity>[],
    );
    entries.insert(
      0,
      TerminalActivity(
        occurredAt: DateTime.now(),
        action: action,
        description: description,
      ),
    );
    if (entries.length > 200) {
      entries.removeRange(200, entries.length);
    }
    notifyListeners();
  }

  void _setState(LocalFileServerState value) {
    _state = value;
    notifyListeners();
  }

  String _verificationCode() => (1000 + _random.nextInt(9000)).toString();
  String _hostDeviceLabel() {
    if (Platform.isAndroid) return '手机';
    if (Platform.isIOS) return '苹果设备';
    return '电脑';
  }

  String _token() =>
      List.generate(32, (_) => _random.nextInt(16).toRadixString(16)).join();
  Future<String> _lanAddress() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (_isPrivateIpv4(address.address)) {
          return address.address;
        }
      }
    }
    return '设备局域网 IP';
  }

  bool _isPrivateIpv4(String address) {
    final octets = address.split('.').map(int.tryParse).toList();
    if (octets.length != 4 || octets.any((octet) => octet == null)) {
      return false;
    }
    return octets[0] == 10 ||
        (octets[0] == 172 && octets[1]! >= 16 && octets[1]! <= 31) ||
        (octets[0] == 192 && octets[1] == 168);
  }

  Directory _resolve(String relative) => Directory(_resolvePath(relative));
  String _resolvePath(String? relative) {
    // HttpRequest.uri.queryParameters and JSON bodies are already decoded.
    // Decoding again corrupts valid non-ASCII virtual paths such as /图片.
    final raw = (relative ?? '/').replaceAll('\\', '/');
    final parts = raw.split('/').where((part) => part.isNotEmpty).map(_segment);
    return '${_shareRoot!.path}${parts.isEmpty ? '' : '${Platform.pathSeparator}${parts.join(Platform.pathSeparator)}'}';
  }

  String _segment(String? value) {
    final result = value?.trim() ?? '';
    if (result.isEmpty ||
        result == '.' ||
        result == '..' ||
        result.contains('/') ||
        result.contains('\\\\') ||
        result.contains('\u0000')) {
      throw FormatException('非法路径');
    }
    return result;
  }

  FileSystemEntity _entity(String? relative) {
    final path = _resolvePath(relative);
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw FileSystemException('文件不存在');
    }
    return type == FileSystemEntityType.directory
        ? Directory(path)
        : File(path);
  }

  String _virtual(String absolute) {
    final root = _shareRoot!.path;
    if (absolute == root) {
      return '/';
    }
    return '/${absolute.substring(root.length).replaceAll('\\', '/').replaceFirst(RegExp(r'^/'), '')}';
  }

  String _name(String path) => path.split(Platform.pathSeparator).last;
  String _parent(String path) =>
      path.substring(0, path.lastIndexOf(Platform.pathSeparator));
  Future<Map<String, dynamic>> _body(HttpRequest request) async =>
      jsonDecode(await utf8.decoder.bind(request).join())
          as Map<String, dynamic>;
  void _json(HttpResponse response, int status, Object data) {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(data));
    response.close();
  }

  void _rangeError(HttpResponse response, int total) {
    response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
    response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
    response.close();
  }

  ContentType _contentType(String path) {
    final extension = path.split('.').last.toLowerCase();
    switch (extension) {
      case 'html':
        return ContentType.html;
      case 'js':
        return ContentType('application', 'javascript', charset: 'utf-8');
      case 'css':
        return ContentType('text', 'css', charset: 'utf-8');
      case 'json':
        return ContentType.json;
      case 'svg':
        return ContentType('image', 'svg+xml');
      case 'png':
        return ContentType('image', 'png');
      case 'jpg':
      case 'jpeg':
        return ContentType('image', 'jpeg');
      case 'mp4':
        return ContentType('video', 'mp4');
      default:
        return ContentType.binary;
    }
  }
}

class _Upload {
  _Upload({
    required this.id,
    required this.name,
    required this.parentPath,
    required this.total,
    required this.chunks,
    required this.temp,
    required this.terminalId,
  });
  final String id, name, parentPath;
  final int total, chunks;
  final Directory temp;
  final String? terminalId;
  final Set<int> received = {};
  Map<String, Object?> json() => {
    'id': id,
    'name': name,
    'size': total,
    'chunks': chunks,
    'uploadedChunks': received.toList(),
  };
}

class _TerminalSocket {
  const _TerminalSocket(this.socket, this.terminal);
  final WebSocket socket;
  final ConnectedTerminal terminal;
}
