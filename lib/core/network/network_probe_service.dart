import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/app_environment.dart';

enum NetworkProbeState {
  idle,
  probing,
  success,
  slow,
  failed,
}

enum NetworkProbeCategory {
  server,
  public,
  custom,
}

class NetworkProbeTarget {
  const NetworkProbeTarget({
    required this.name,
    required this.url,
    required this.category,
    this.isBuiltin = true,
  });

  final String name;
  final String url;
  final NetworkProbeCategory category;
  final bool isBuiltin;

  Map<String, dynamic> toJson() => {
        'name': name,
        'url': url,
        'category': category.name,
        'isBuiltin': isBuiltin,
      };

  factory NetworkProbeTarget.fromJson(Map<String, dynamic> json) {
    return NetworkProbeTarget(
      name: json['name'] as String? ?? '',
      url: json['url'] as String? ?? '',
      category: NetworkProbeCategory.values.firstWhere(
        (c) => c.name == json['category'],
        orElse: () => NetworkProbeCategory.custom,
      ),
      isBuiltin: json['isBuiltin'] as bool? ?? false,
    );
  }
}

class NetworkProbeResult {
  const NetworkProbeResult({
    required this.target,
    required this.state,
    this.dnsTimeMs,
    this.httpLatencyMs,
    this.statusCode,
    this.errorMessage,
    this.ipAddress,
  });

  final NetworkProbeTarget target;
  final NetworkProbeState state;
  final int? dnsTimeMs;
  final int? httpLatencyMs;
  final int? statusCode;
  final String? errorMessage;
  final String? ipAddress;

  int get totalLatencyMs => (dnsTimeMs ?? 0) + (httpLatencyMs ?? 0);

  NetworkProbeResult copyWith({
    NetworkProbeTarget? target,
    NetworkProbeState? state,
    int? dnsTimeMs,
    int? httpLatencyMs,
    int? statusCode,
    String? errorMessage,
    String? ipAddress,
  }) {
    return NetworkProbeResult(
      target: target ?? this.target,
      state: state ?? this.state,
      dnsTimeMs: dnsTimeMs ?? this.dnsTimeMs,
      httpLatencyMs: httpLatencyMs ?? this.httpLatencyMs,
      statusCode: statusCode ?? this.statusCode,
      errorMessage: errorMessage ?? this.errorMessage,
      ipAddress: ipAddress ?? this.ipAddress,
    );
  }
}

class NetworkDiagnosticSummary {
  const NetworkDiagnosticSummary({
    required this.title,
    required this.detail,
    required this.isHealthy,
    required this.isLocalNetworkIssue,
    required this.isServerIssue,
  });

  final String title;
  final String detail;
  final bool isHealthy;
  final bool isLocalNetworkIssue;
  final bool isServerIssue;
}

/// Diagnoses network connectivity, DNS resolution, and latency for:
/// 1. Internal server endpoints (API, Auth, SignalR Hub)
/// 2. Common public networks (Baidu, Bilibili, Tencent, Cloudflare, Google)
/// 3. User-defined custom URLs (persisted locally)
class NetworkProbeService extends ChangeNotifier {
  NetworkProbeService({
    required AppEnvironment environment,
    FlutterSecureStorage? storage,
  })  : _environment = environment,
        _storage = storage ?? const FlutterSecureStorage() {
    _initBuiltinTargets();
    _loadCustomTargets();
  }

  final AppEnvironment _environment;
  final FlutterSecureStorage _storage;
  static const String _storageKey = 'gotoim.custom_probe_urls';

  final List<NetworkProbeTarget> _builtinTargets = [];
  final List<NetworkProbeTarget> _customTargets = [];
  final Map<String, NetworkProbeResult> _results = {};
  bool _isProbing = false;

  bool get isProbing => _isProbing;
  List<NetworkProbeTarget> get allTargets => [..._builtinTargets, ..._customTargets];
  List<NetworkProbeTarget> get customTargets => List.unmodifiable(_customTargets);
  Map<String, NetworkProbeResult> get results => Map.unmodifiable(_results);

  void _initBuiltinTargets() {
    _builtinTargets.clear();

    // 1. Server Endpoints
    _builtinTargets.add(
      NetworkProbeTarget(
        name: 'IM API 服务',
        url: _environment.apiBaseUrl,
        category: NetworkProbeCategory.server,
      ),
    );
    _builtinTargets.add(
      NetworkProbeTarget(
        name: 'OpenID 认证服务',
        url: _environment.authBaseUrl,
        category: NetworkProbeCategory.server,
      ),
    );
    _builtinTargets.add(
      NetworkProbeTarget(
        name: 'SignalR Hub 服务',
        url: _environment.signalRHubUrl,
        category: NetworkProbeCategory.server,
      ),
    );

    // 2. Public Common Networks
    _builtinTargets.add(
      const NetworkProbeTarget(
        name: '百度 (Baidu)',
        url: 'https://www.baidu.com',
        category: NetworkProbeCategory.public,
      ),
    );
    _builtinTargets.add(
      const NetworkProbeTarget(
        name: '哔哩哔哩 (Bilibili)',
        url: 'https://www.bilibili.com',
        category: NetworkProbeCategory.public,
      ),
    );
    _builtinTargets.add(
      const NetworkProbeTarget(
        name: '腾讯网 (Tencent)',
        url: 'https://www.qq.com',
        category: NetworkProbeCategory.public,
      ),
    );
    _builtinTargets.add(
      const NetworkProbeTarget(
        name: 'Cloudflare DNS',
        url: 'https://1.1.1.1',
        category: NetworkProbeCategory.public,
      ),
    );
    _builtinTargets.add(
      const NetworkProbeTarget(
        name: 'Google 连通性测试',
        url: 'https://connectivitycheck.gstatic.com/generate_204',
        category: NetworkProbeCategory.public,
      ),
    );

    for (final t in _builtinTargets) {
      _results[t.url] = NetworkProbeResult(target: t, state: NetworkProbeState.idle);
    }
  }

  Future<void> _loadCustomTargets() async {
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _customTargets.clear();
          for (final item in decoded) {
            if (item is Map) {
              final target = NetworkProbeTarget.fromJson(Map<String, dynamic>.from(item));
              _customTargets.add(target);
              _results[target.url] = NetworkProbeResult(target: target, state: NetworkProbeState.idle);
            }
          }
          notifyListeners();
        }
      }
    } catch (_) {}
  }

  Future<void> _saveCustomTargets() async {
    try {
      final list = _customTargets.map((t) => t.toJson()).toList();
      await _storage.write(key: _storageKey, value: jsonEncode(list));
    } catch (_) {}
  }

  Future<void> addCustomTarget(String url, {String? name}) async {
    var cleanUrl = url.trim();
    if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
      cleanUrl = 'https://$cleanUrl';
    }
    final targetName = (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : (Uri.tryParse(cleanUrl)?.host ?? cleanUrl);

    // Don't add duplicate URL
    if (allTargets.any((t) => t.url == cleanUrl)) return;

    final target = NetworkProbeTarget(
      name: targetName,
      url: cleanUrl,
      category: NetworkProbeCategory.custom,
      isBuiltin: false,
    );
    _customTargets.add(target);
    _results[cleanUrl] = NetworkProbeResult(target: target, state: NetworkProbeState.idle);
    await _saveCustomTargets();
    notifyListeners();
  }

  Future<void> removeCustomTarget(String url) async {
    _customTargets.removeWhere((t) => t.url == url);
    _results.remove(url);
    await _saveCustomTargets();
    notifyListeners();
  }

  Future<void> probeAll() async {
    if (_isProbing) return;
    _isProbing = true;
    notifyListeners();

    try {
      final futures = allTargets.map((t) => probeTarget(t));
      await Future.wait(futures);
    } finally {
      _isProbing = false;
      notifyListeners();
    }
  }

  Future<NetworkProbeResult> probeTarget(NetworkProbeTarget target) async {
    _results[target.url] = NetworkProbeResult(
      target: target,
      state: NetworkProbeState.probing,
    );
    notifyListeners();

    final result = await _executeProbe(target);
    _results[target.url] = result;
    notifyListeners();
    return result;
  }

  Future<NetworkProbeResult> _executeProbe(NetworkProbeTarget target) async {
    final uri = Uri.tryParse(target.url);
    if (uri == null || uri.host.isEmpty) {
      return NetworkProbeResult(
        target: target,
        state: NetworkProbeState.failed,
        errorMessage: 'URL 格式不合法',
      );
    }

    int? dnsTime;
    String? ip;
    // 1. DNS Lookup
    final dnsStopwatch = Stopwatch()..start();
    try {
      final addresses = await InternetAddress.lookup(uri.host).timeout(
        const Duration(seconds: 4),
      );
      dnsStopwatch.stop();
      dnsTime = dnsStopwatch.elapsedMilliseconds;
      if (addresses.isNotEmpty) {
        ip = addresses.first.address;
      }
    } catch (e) {
      dnsStopwatch.stop();
      return NetworkProbeResult(
        target: target,
        state: NetworkProbeState.failed,
        dnsTimeMs: dnsStopwatch.elapsedMilliseconds,
        errorMessage: 'DNS 解析失败: ${e.toString().split('\n').first}',
      );
    }

    // 2. HTTP Probe
    final httpStopwatch = Stopwatch()..start();
    HttpClient? client;
    try {
      client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5)
        ..badCertificateCallback = (cert, host, port) => true; // Diagnostic tool probes even self-signed

      final request = await client.getUrl(uri).timeout(
        const Duration(seconds: 5),
      );
      request.followRedirects = true;
      request.maxRedirects = 3;

      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      // Read small body chunk or drain
      await response.drain<void>().timeout(const Duration(seconds: 2)).catchError((Object _) {});
      httpStopwatch.stop();
      final latency = httpStopwatch.elapsedMilliseconds;
      final code = response.statusCode;

      // Status 200..399 or 401/403/404 are reachable
      final isReachable = code < 500;
      final isSlow = (latency + dnsTime) > 1000;

      return NetworkProbeResult(
        target: target,
        state: isReachable
            ? (isSlow ? NetworkProbeState.slow : NetworkProbeState.success)
            : NetworkProbeState.failed,
        dnsTimeMs: dnsTime,
        httpLatencyMs: latency,
        statusCode: code,
        ipAddress: ip,
        errorMessage: isReachable ? null : '服务器返回 HTTP $code',
      );
    } catch (e) {
      httpStopwatch.stop();
      return NetworkProbeResult(
        target: target,
        state: NetworkProbeState.failed,
        dnsTimeMs: dnsTime,
        httpLatencyMs: httpStopwatch.elapsedMilliseconds,
        ipAddress: ip,
        errorMessage: _formatHttpError(e),
      );
    } finally {
      client?.close(force: true);
    }
  }

  String _formatHttpError(Object error) {
    final msg = error.toString();
    if (msg.contains('timed out') || msg.contains('TimeoutException')) {
      return '连接超时 (大于 5 秒)';
    }
    if (msg.contains('Connection refused')) {
      return '连接被拒绝 (端口未开放)';
    }
    if (msg.contains('Failed host lookup')) {
      return '无法解析主机域名';
    }
    if (msg.contains('Network is unreachable') || msg.contains('SocketException')) {
      return '网络不可达';
    }
    return msg.split('\n').first;
  }

  NetworkDiagnosticSummary get summary {
    final publicResults = _results.values
        .where((r) => r.target.category == NetworkProbeCategory.public && r.state != NetworkProbeState.idle && r.state != NetworkProbeState.probing)
        .toList();
    final serverResults = _results.values
        .where((r) => r.target.category == NetworkProbeCategory.server && r.state != NetworkProbeState.idle && r.state != NetworkProbeState.probing)
        .toList();

    if (publicResults.isEmpty && serverResults.isEmpty) {
      return const NetworkDiagnosticSummary(
        title: '未开始测试',
        detail: '点击下方"测试全部网络与服务"，分析网络连通性及延时。',
        isHealthy: true,
        isLocalNetworkIssue: false,
        isServerIssue: false,
      );
    }

    final publicFailCount = publicResults.where((r) => r.state == NetworkProbeState.failed).length;
    final serverFailCount = serverResults.where((r) => r.state == NetworkProbeState.failed).length;

    // 1. All public networks failed -> Local device network down
    if (publicResults.isNotEmpty && publicFailCount == publicResults.length) {
      return const NetworkDiagnosticSummary(
        title: '本地网络无外网访问',
        detail: '所有公网站点（百度、腾讯、Cloudflare）均无法连通，请检查手机 Wi-Fi 或移动蜂窝数据设置。',
        isHealthy: false,
        isLocalNetworkIssue: true,
        isServerIssue: false,
      );
    }

    // 2. Public networks pass, but server endpoints fail -> Server down / unreachable
    if (publicFailCount == 0 && serverResults.isNotEmpty && serverFailCount > 0) {
      final firstFailed = serverResults.firstWhere((r) => r.state == NetworkProbeState.failed);
      return NetworkDiagnosticSummary(
        title: 'IM 服务器连接异常',
        detail: '外网访问正常，但 IM 服务器无法连通（${firstFailed.target.name}：${firstFailed.errorMessage ?? '连接失败'}）。请确认服务端是否启动或存在防火墙拦截。',
        isHealthy: false,
        isLocalNetworkIssue: false,
        isServerIssue: true,
      );
    }

    // 3. Server returned 401
    final server401 = serverResults.any((r) => r.statusCode == 401);
    if (server401) {
      return const NetworkDiagnosticSummary(
        title: '登录凭据需要刷新 (HTTP 401)',
        detail: '网络与服务器物理连通正常，但身份认证令牌已过期，系统正在自动刷新 Token。',
        isHealthy: false,
        isLocalNetworkIssue: false,
        isServerIssue: false,
      );
    }

    // 4. Slow connection
    final hasSlow = [...publicResults, ...serverResults].any((r) => r.state == NetworkProbeState.slow);
    if (hasSlow) {
      return const NetworkDiagnosticSummary(
        title: '网络延时偏高',
        detail: '网络与服务器均可连通，但部分请求延时超过 1000ms，可能影响消息即时性。',
        isHealthy: true,
        isLocalNetworkIssue: false,
        isServerIssue: false,
      );
    }

    return const NetworkDiagnosticSummary(
      title: '网络与服务连通正常',
      detail: '本地外网连接良好，IM API、认证服务及 SignalR 实时 Hub 均可正常通信。',
      isHealthy: true,
      isLocalNetworkIssue: false,
      isServerIssue: false,
    );
  }
}

final networkProbeServiceProvider = ChangeNotifierProvider<NetworkProbeService>((ref) {
  final service = NetworkProbeService(
    environment: ref.watch(appEnvironmentProvider),
  );
  return service;
});
