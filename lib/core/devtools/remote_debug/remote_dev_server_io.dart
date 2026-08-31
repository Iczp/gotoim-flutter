import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import '../../logging/app_logger.dart';
import '../../logging/diagnostic_log_entry.dart';
import 'remote_dev_config.dart';

class RemoteDevServer {
  RemoteDevServer({RemoteDevConfig? config})
      : _config = config ?? const RemoteDevConfig();

  final RemoteDevConfig _config;
  final Set<WebSocket> _clients = <WebSocket>{};
  final List<DiagnosticLogEntry> _pending = <DiagnosticLogEntry>[];
  HttpServer? _server;
  StreamSubscription<List<DiagnosticLogEntry>>? _logSubscription;
  Timer? _flushTimer;
  bool _snapshotActive = false;
  DateTime? _snapshotStartedAt;
  String? _lanAddress;

  bool get isRunning => _server != null;
  int get port => _server?.port ?? _config.port;
  int get clientCount => _clients.length;
  String? get url {
    final boundAddress = _server?.address;
    final address = _lanAddress ??
        (boundAddress != null && boundAddress.isLoopback
            ? boundAddress.address
            : null);
    if (address == null) return null;
    return 'http://$address:$port';
  }

  Future<void> start() async {
    if (isRunning || !_config.enabled) return;
    final address = _config.allowRemoteAccess
        ? InternetAddress.anyIPv4
        : InternetAddress.loopbackIPv4;
    _server = await HttpServer.bind(address, _config.port, shared: true);
    _lanAddress =
        _config.allowRemoteAccess ? await _findLanAddress() : '127.0.0.1';
    _logSubscription = AppLogger.instance.store.changes.listen(_onLogs);
    unawaited(_listen());
    AppLogger.instance.info('Remote DevTools server started',
        category: 'devtools',
        event: 'remote_server_started',
        context: <String, Object?>{
          'port': port,
          'allowRemoteAccess': _config.allowRemoteAccess
        });
  }

  Future<void> stop() async {
    final server = _server;
    if (server == null) return;
    _server = null;
    _flushTimer?.cancel();
    _flushTimer = null;
    await _logSubscription?.cancel();
    _logSubscription = null;
    for (final client in _clients) {
      await client.close();
    }
    _clients.clear();
    await server.close(force: true);
    _lanAddress = null;
  }

  Future<void> _listen() async {
    try {
      await for (final request in _server!) {
        unawaited(_handle(request));
      }
    } catch (_) {
      // Closing the server terminates the request stream normally for callers.
    }
  }

  Future<String?> _findLanAddress() async {
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
    return null;
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

  Future<void> _handle(HttpRequest request) async {
    try {
      if (request.uri.path == '/ws/logs' &&
          WebSocketTransformer.isUpgradeRequest(request)) {
        final socket = await WebSocketTransformer.upgrade(request);
        _clients.add(socket);
        socket.listen((_) {},
            onDone: () => _clients.remove(socket),
            onError: (_) => _clients.remove(socket));
        _send(socket, <String, Object?>{'type': 'status', 'data': _status()});
        _send(socket, <String, Object?>{
          'type': 'logs',
          'items': AppLogger.instance.store.entries
              .map((item) => item.toJson())
              .toList()
        });
        return;
      }
      final path = request.uri.path;
      if (path == '/' ||
          path == '/index.html' ||
          path.startsWith('/assets/') ||
          path == '/app.js' ||
          path == '/app.css' ||
          path == '/favicon.svg') {
        await _serveAsset(request);
        return;
      }
      if (path == '/api/status') {
        await _json(request, _status());
        return;
      }
      if (path == '/api/device') {
        await _json(request, <String, Object?>{
          'platform': Platform.operatingSystem,
          'osVersion': Platform.operatingSystemVersion,
          'serverAddress': _server?.address.address,
          'port': port
        });
        return;
      }
      if (path == '/api/diagnostic-bundle') {
        await _json(request, _diagnosticBundle());
        return;
      }
      if (path == '/api/logs' && request.method == 'DELETE') {
        AppLogger.instance.store.clear();
        _broadcast(<String, Object?>{'type': 'server_clear'});
        await _json(request, <String, Object?>{'success': true});
        return;
      }
      if (path == '/api/logs' || path == '/api/logs/search') {
        await _logs(request);
        return;
      }
      if (path == '/api/errors') {
        await _errors(request);
        return;
      }
      if (path.startsWith('/api/trace/')) {
        await _trace(
            request, Uri.decodeComponent(path.substring('/api/trace/'.length)));
        return;
      }
      if (path == '/api/capture/start' && request.method == 'POST') {
        AppLogger.instance.setCaptureEnabled(true);
        await _state(request);
        return;
      }
      if (path == '/api/capture/stop' && request.method == 'POST') {
        AppLogger.instance.setCaptureEnabled(false);
        await _state(request);
        return;
      }
      if (path == '/api/marker' && request.method == 'POST') {
        final body = await _body(request);
        AppLogger.instance.marker(body['message']?.toString() ?? 'Marker');
        await _json(request, <String, Object?>{'success': true});
        return;
      }
      if (path == '/api/snapshot/start' && request.method == 'POST') {
        _snapshotActive = true;
        _snapshotStartedAt = DateTime.now();
        AppLogger.instance.marker('Snapshot started');
        await _state(request);
        return;
      }
      if (path == '/api/snapshot/stop' && request.method == 'POST') {
        _snapshotActive = false;
        AppLogger.instance.marker('Snapshot stopped');
        await _state(request);
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await _json(request, <String, Object?>{'error': 'Not found'});
      return;
    } catch (error, stack) {
      AppLogger.instance.error('Remote DevTools request failed',
          category: 'devtools',
          event: 'remote_request_failed',
          error: error,
          stackTrace: stack);
      try {
        request.response.statusCode = 500;
        await _json(
            request, <String, Object?>{'error': 'Internal server error'});
      } catch (_) {}
    }
  }

  Future<void> _logs(HttpRequest request) => _json(request, <String, Object?>{
        'items': AppLogger.instance.store
            .search(
                query: request.uri.queryParameters['q'],
                level: request.uri.queryParameters['level'],
                category: request.uri.queryParameters['category'],
                traceId: request.uri.queryParameters['traceId'],
                limit:
                    int.tryParse(request.uri.queryParameters['limit'] ?? '') ??
                        500)
            .map((item) => item.toJson())
            .toList()
      });
  Future<void> _trace(HttpRequest request, String traceId) =>
      _json(request, <String, Object?>{
        'items': AppLogger.instance.store
            .search(traceId: traceId, limit: 5000)
            .map((item) => item.toJson())
            .toList()
      });
  Future<void> _errors(HttpRequest request) {
    final groups = <String, List<DiagnosticLogEntry>>{};
    for (final entry in AppLogger.instance.store.entries
        .where((item) => item.level.isError)) {
      (groups['${entry.error?.type ?? entry.level.value}: ${entry.error?.message ?? entry.message}'] ??=
              <DiagnosticLogEntry>[])
          .add(entry);
    }
    return _json(request, <String, Object?>{
      'items': groups.entries
          .map((entry) => <String, Object?>{
                'message': entry.key,
                'count': entry.value.length,
                'first': entry.value.first.toJson(),
                'last': entry.value.last.toJson()
              })
          .toList()
    });
  }

  Future<void> _state(HttpRequest request) {
    final data = _status();
    _broadcast(<String, Object?>{'type': 'capture_state', 'data': data});
    return _json(request, data);
  }

  Map<String, Object?> _status() => <String, Object?>{
        'running': isRunning,
        'port': port,
        'url': url,
        'clients': clientCount,
        'logs': AppLogger.instance.store.length,
        'captureEnabled': AppLogger.instance.captureEnabled,
        'snapshotActive': _snapshotActive,
        'snapshotStartedAt': _snapshotStartedAt?.toUtc().toIso8601String()
      };

  Map<String, Object?> _diagnosticBundle() {
    final entries = AppLogger.instance.store.entries;
    final errors = entries.where((entry) => entry.level.isError).toList();
    final primary = errors.isEmpty ? null : errors.last;
    final source = primary?.source;
    final readme = StringBuffer('# GotoIM Diagnostic Bundle\n\n')
      ..writeln('## Primary Error')
      ..writeln(
          primary?.error?.message ?? primary?.message ?? 'No error captured')
      ..writeln('\n## Source')
      ..writeln(source == null
          ? 'No application source frame captured.'
          : '${source.file}:${source.line ?? ''}:${source.column ?? ''}')
      ..writeln('\n## TraceId')
      ..writeln(primary?.traceId ?? 'Not available')
      ..writeln('\n## Relevant Source Files');
    for (final file in primary?.relatedFiles ?? const <String>[]) {
      readme.writeln('- $file');
    }
    return <String, Object?>{
      'schema': 'gotoim-diagnostic/v1',
      'README.md': readme.toString(),
      'manifest.json': <String, Object?>{
        'schema': 'gotoim-diagnostic/v1',
        'app': <String, Object?>{'name': 'GotoIM', 'version': '0.1.0+1'},
        'runtime': <String, Object?>{
          'mode': 'debug',
          'platform': Platform.operatingSystem
        },
      },
      'errors.json': errors.map((entry) => entry.toJson()).toList(),
      'logs.jsonl':
          entries.map((entry) => jsonEncode(entry.toJson())).join('\n'),
      'device.json': <String, Object?>{
        'platform': Platform.operatingSystem,
        'osVersion': Platform.operatingSystemVersion
      },
    };
  }

  void _onLogs(List<DiagnosticLogEntry> items) {
    if (items.isEmpty) return;
    _pending.addAll(items);
    _flushTimer ??= Timer(const Duration(milliseconds: 50), _flush);
  }

  void _flush() {
    _flushTimer = null;
    if (_pending.isEmpty) return;
    final entries = List<DiagnosticLogEntry>.from(_pending);
    _pending.clear();
    _broadcast(<String, Object?>{
      'type': 'logs',
      'items': entries.map((item) => item.toJson()).toList()
    });
  }

  void _broadcast(Map<String, Object?> data) {
    for (final client in List<WebSocket>.from(_clients)) {
      _send(client, data);
    }
  }

  void _send(WebSocket socket, Map<String, Object?> data) {
    try {
      socket.add(jsonEncode(data));
    } catch (_) {
      _clients.remove(socket);
    }
  }

  Future<Map<String, Object?>> _body(HttpRequest request) async {
    final raw = await utf8.decoder.bind(request).join();
    if (raw.trim().isEmpty) return <String, Object?>{};
    final json = jsonDecode(raw);
    return json is Map ? Map<String, Object?>.from(json) : <String, Object?>{};
  }

  Future<void> _json(HttpRequest request, Object data) async {
    request.response.headers.contentType = ContentType.json;
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.write(jsonEncode(data));
    await request.response.close();
  }

  Future<void> _serveAsset(HttpRequest request) async {
    final rawPath = request.uri.path;
    final assetPath = rawPath == '/' ? 'index.html' : rawPath.substring(1);
    if (assetPath.contains('..')) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    try {
      final data = await rootBundle.load('assets/devtools/remote/$assetPath');
      request.response.headers.contentType = _contentType(assetPath);
      request.response.add(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } catch (_) {
      try {
        final indexData =
            await rootBundle.load('assets/devtools/remote/index.html');
        request.response.headers.contentType = ContentType.html;
        request.response.add(
          indexData.buffer.asUint8List(
              indexData.offsetInBytes, indexData.lengthInBytes),
        );
      } catch (_) {
        request.response.headers.contentType = ContentType.html;
        request.response.write(_page);
      }
    }
    await request.response.close();
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
      case 'woff2':
        return ContentType('font', 'woff2');
      case 'woff':
        return ContentType('font', 'woff');
      case 'ttf':
        return ContentType('font', 'ttf');
      default:
        return ContentType.binary;
    }
  }
}

const String _page =
    r'''<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>GotoIM Remote DevTools</title><style>body{margin:0;background:#101418;color:#e7edf4;font:14px system-ui}header{padding:14px 18px;background:#18212b;position:sticky;top:0}button,input,select{margin:3px;padding:7px;background:#263340;color:#e7edf4;border:1px solid #435466;border-radius:5px}#logs{height:calc(100vh - 130px);overflow:auto;font:12px ui-monospace,monospace}.row{height:22px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;padding:2px 12px;border-bottom:1px solid #1c2630}.error,.fatal{color:#ff8996}.warning{color:#ffd178}.debug{color:#8aa2b5}.detail{padding:10px;white-space:pre-wrap;background:#18212b;max-height:25vh;overflow:auto}</style></head><body><header><b>GotoIM Remote DevTools</b><span id="status"></span><br><button onclick="capture(true)">Start capture</button><button onclick="capture(false)">Stop capture</button><button onclick="pause()" id="pause">Pause view</button><button onclick="clearServer()">Clear server</button><button onclick="marker()">Marker</button><input id="q" placeholder="Search" oninput="render()"><select id="level" onchange="render()"><option value="">All levels</option><option>error</option><option>warning</option><option>info</option><option>debug</option></select></header><div id="logs"></div><pre id="detail" class="detail">Select a log entry to view sanitized JSON.</pre><script>let all=[],paused=false;const e=x=>document.getElementById(x);function render(){let q=e('q').value.toLowerCase(),l=e('level').value,items=all.filter(x=>(!q||JSON.stringify(x).toLowerCase().includes(q))&&(!l||x.level===l));e('logs').innerHTML=items.slice(-1000).map(x=>`<div class="row ${x.level}" onclick='show("${x.id}")'>${x.timestamp} [${x.level}] ${x.category}/${x.event}: ${esc(x.message)}</div>`).join('');e('status').textContent=` Logs: ${all.length} Visible: ${items.length} WS: connected`; }function esc(x){return String(x).replace(/[&<>]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]))}function show(id){e('detail').textContent=JSON.stringify(all.find(x=>x.id===id),null,2)}function pause(){paused=!paused;e('pause').textContent=paused?'Resume view':'Pause view';if(!paused)render()}async function api(path,method='POST',body){return fetch(path,{method,headers:{'content-type':'application/json'},body:body&&JSON.stringify(body)})}function capture(v){api('/api/capture/'+(v?'start':'stop'))}function clearServer(){api('/api/logs','DELETE');all=[];render()}function marker(){let m=prompt('Marker');if(m)api('/api/marker','POST',{message:m})}fetch('/api/logs?limit=5000').then(r=>r.json()).then(x=>{all=x.items;render()});let ws=new WebSocket(`ws://${location.host}/ws/logs`);ws.onmessage=x=>{let d=JSON.parse(x.data);if(d.type==='logs'){all.push(...d.items);if(all.length>10000)all.splice(0,all.length-10000);if(!paused)render()}if(d.type==='server_clear'){all=[];render()}};</script></body></html>''';
